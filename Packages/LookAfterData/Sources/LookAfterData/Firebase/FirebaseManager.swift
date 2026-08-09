import Foundation
import CryptoKit
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import LookAfterCore

/// Central Firebase manager — handles authentication and Firestore database access.
/// All data flows through this manager for consistent access control.
@MainActor
public final class FirebaseManager: ObservableObject {
    
    @Published public var currentUserId: String?
    @Published public var isAuthenticated: Bool = false
    @Published public var userEmail: String? = UserDefaults.standard.string(forKey: "userEmail")
    @Published public var error: String?
    
    public var db: Firestore? {
        LookAfterFirebaseConfiguration.configureIfNeeded()
        ensureAuthListener()
        return FirebaseApp.app() != nil ? Firestore.firestore() : nil
    }

    /// True when Firestore reads/writes are allowed (real Firebase Auth + non-mock project).
    public var isCloudSyncAvailable: Bool {
        guard FirebaseApp.app() != nil, Auth.auth().currentUser != nil else { return false }
        guard let projectID = FirebaseApp.app()?.options.projectID else { return false }
        return !Self.mockProjectIDs.contains(projectID)
    }

    private static let mockProjectIDs: Set<String> = ["lifeos-mock", "lifeos-dummy"]
    
    private var authListener: AuthStateDidChangeListenerHandle?
    
    public static let shared: FirebaseManager = {
        LookAfterFirebaseConfiguration.configureIfNeeded()
        return FirebaseManager()
    }()
    
    private init() {
        LookAfterFirebaseConfiguration.configureIfNeeded()
        let savedUid = UserDefaults.standard.string(forKey: "saved_user_uid")
        let savedEmail = UserDefaults.standard.string(forKey: "userEmail")
        if let uid = savedUid, !uid.isEmpty {
            self.currentUserId = uid
            self.userEmail = savedEmail
            self.isAuthenticated = true
        }
        ensureAuthListener()
    }
    
    // MARK: - Auth
    
    private func ensureAuthListener() {
        guard authListener == nil, FirebaseApp.app() != nil else { return }
        setupAuthListener()
    }

    private func setupAuthListener() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                if let user {
                    self.applyAuthenticatedUser(user)
                } else if self.usesRealFirebaseAuth {
                    // Real Auth session ended (sign-out, revoke, expiry).
                    // Do not clear offline/mock local sessions driven by synthetic UIDs.
                    self.clearLocalAuthState()
                }
            }
        }
    }

    /// Stable account id for local storage — prefers Firebase Auth UID.
    public var resolvedUserId: String {
        if FirebaseApp.app() != nil,
           let uid = Auth.auth().currentUser?.uid,
           !uid.isEmpty {
            return uid
        }
        if let uid = currentUserId, !uid.isEmpty { return uid }
        return UserDefaults.standard.string(forKey: "saved_user_uid") ?? ""
    }
    
    /// True when Firebase is configured with a non-mock project that can perform real Auth.
    private var usesRealFirebaseAuth: Bool {
        guard FirebaseApp.app() != nil,
              let projectID = FirebaseApp.app()?.options.projectID,
              !projectID.isEmpty else { return false }
        return !Self.mockProjectIDs.contains(projectID)
            && projectID != "flowos-test-app"
    }

    /// Sign in anonymously for quick start (no account required).
    public func signInAnonymously() async throws {
        if usesRealFirebaseAuth {
            do {
                let result = try await Auth.auth().signInAnonymously()
                applyAuthenticatedUser(result.user)
            } catch {
                self.error = error.localizedDescription
                throw error
            }
            return
        }

        // Offline / mock projects: stable local guest identity (no network).
        let fallbackUid = UserDefaults.standard.string(forKey: "saved_user_uid")
            ?? "guest_\(UUID().uuidString.prefix(8))"
        applyLocalAuthenticatedSession(userId: fallbackUid, email: nil)
    }

    /// Sign in with email/password.
    public func signIn(email: String, password: String) async throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty else {
            throw FirebaseManagerError.ssoFailed("Email is required.")
        }
        guard !password.isEmpty else {
            throw FirebaseManagerError.ssoFailed("Password is required.")
        }

        if usesRealFirebaseAuth {
            do {
                let result = try await Auth.auth().signIn(withEmail: normalizedEmail, password: password)
                applyAuthenticatedUser(result.user)
            } catch {
                clearLocalAuthState()
                self.error = error.localizedDescription
                throw error
            }
            return
        }

        // Offline / mock projects: stable local identity from email (no network).
        applyLocalAuthenticatedSession(
            userId: Self.stableLocalUserId(forEmail: normalizedEmail),
            email: normalizedEmail
        )
    }

    /// Create account with email/password.
    public func createAccount(email: String, password: String) async throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty else {
            throw FirebaseManagerError.ssoFailed("Email is required.")
        }
        guard !password.isEmpty else {
            throw FirebaseManagerError.ssoFailed("Password is required.")
        }

        if usesRealFirebaseAuth {
            do {
                let result = try await Auth.auth().createUser(withEmail: normalizedEmail, password: password)
                applyAuthenticatedUser(result.user)
            } catch {
                clearLocalAuthState()
                self.error = error.localizedDescription
                throw error
            }
            return
        }

        applyLocalAuthenticatedSession(
            userId: Self.stableLocalUserId(forEmail: normalizedEmail),
            email: normalizedEmail
        )
    }

    /// Sign out.
    public func signOut() throws {
        if FirebaseApp.app() != nil {
            try? Auth.auth().signOut()
        }
        clearLocalAuthState()
        LicenseManager.shared.clearLocalLicense()
    }

    /// Firebase ID token for Azure auth-proxy calls.
    public func idToken(forceRefresh: Bool = false) async throws -> String? {
        guard FirebaseApp.app() != nil, let user = Auth.auth().currentUser else { return nil }
        return try await user.getIDToken(forcingRefresh: forceRefresh)
    }

    /// Sign in with Apple (AuthenticationServices → Firebase).
    public func signInWithApple() async throws {
        guard usesRealFirebaseAuth else {
            throw FirebaseManagerError.ssoFailed("Firebase is not configured")
        }
        let coordinator = AppleSignInCoordinator()
        let credential = try await coordinator.signIn()
        let result = try await Auth.auth().signIn(with: credential)
        applyAuthenticatedUser(result.user)
        if let fullName = result.user.displayName, !fullName.isEmpty {
            UserDefaults.standard.set(fullName, forKey: "userName")
        }
    }

    /// Sign in with Google via Firebase OAuth provider (browser sheet). Available on iOS.
    public func signInWithGoogle() async throws {
        guard usesRealFirebaseAuth else {
            throw FirebaseManagerError.ssoFailed("Firebase is not configured")
        }
        #if os(iOS)
        let provider = OAuthProvider(providerID: "google.com")
        provider.scopes = ["email", "profile", "https://www.googleapis.com/auth/gmail.readonly"]
        let credential = try await provider.credential(with: nil)
        let result = try await Auth.auth().signIn(with: credential)
        applyAuthenticatedUser(result.user)
        if let name = result.user.displayName, !name.isEmpty {
            UserDefaults.standard.set(name, forKey: "userName")
        }
        #else
        throw FirebaseManagerError.ssoFailed("Google Sign-In is available on iOS. Use Apple or email on Mac.")
        #endif
    }

    private func applyAuthenticatedUser(_ user: User) {
        applyLocalAuthenticatedSession(userId: user.uid, email: user.email ?? userEmail)
    }

    private func applyLocalAuthenticatedSession(userId: String, email: String?) {
        let previous = currentUserId
        currentUserId = userId
        userEmail = email
        isAuthenticated = true
        error = nil
        UserDefaults.standard.set(userId, forKey: "saved_user_uid")
        if let email, !email.isEmpty {
            UserDefaults.standard.set(email, forKey: "userEmail")
        } else {
            UserDefaults.standard.removeObject(forKey: "userEmail")
        }
        if let previous, !previous.isEmpty, previous != userId {
            HealthSummaryRepository().reassignSummaries(from: previous, to: userId)
            TaskStore.shared.reassignTasks(from: previous, to: userId)
        }
    }

    private func clearLocalAuthState() {
        currentUserId = nil
        isAuthenticated = false
        userEmail = nil
        error = nil
        UserDefaults.standard.removeObject(forKey: "saved_user_uid")
        UserDefaults.standard.removeObject(forKey: "userEmail")
    }

    /// Stable offline identity for mock Auth — not `String.hashValue` (process-unstable).
    private static func stableLocalUserId(forEmail email: String) -> String {
        let digest = SHA256.hash(data: Data(email.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "usr_\(hex.prefix(16))"
    }

    // MARK: - Firestore Helpers
    
    /// Get a reference to a user's collection.
    public func userCollection(_ collection: String) -> CollectionReference? {
        guard isCloudSyncAvailable, let userId = Auth.auth().currentUser?.uid else { return nil }
        return db?.collection("users").document(userId).collection(collection)
    }
    
    /// Encode a Codable object to Firestore-compatible dictionary.
    public func encode<T: Encodable>(_ item: T) throws -> [String: Any] {
        let data = try SharedFormatters.jsonEncoderSeconds.encode(item)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FirebaseManagerError.encodingError
        }
        return dict
    }
    
    /// Decode a Firestore document to a Codable object.
    public func decode<T: Decodable>(_ type: T.Type, from document: DocumentSnapshot) throws -> T {
        guard let data = document.data() else {
            throw FirebaseManagerError.documentNotFound
        }
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        
        let decoder = SharedFormatters.jsonDecoderSeconds
        return try decoder.decode(type, from: jsonData)
    }
}

// MARK: - Errors

public enum FirebaseManagerError: Error, LocalizedError {
    case notAuthenticated
    case documentNotFound
    case encodingError
    case collectionNotFound
    case ssoFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "User not authenticated"
        case .documentNotFound: return "Document not found"
        case .encodingError: return "Failed to encode data"
        case .collectionNotFound: return "Collection not found"
        case .ssoFailed(let message): return message
        }
    }
}
