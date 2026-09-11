import Foundation
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
        // Restore local session for offline continuity. Firebase Auth listener
        // will clear flags if the remote user is nil (revoked / signed out elsewhere).
        // Local SQLite/JSON rows are never deleted by session-flag clears.
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
                    let previous = self.currentUserId
                    self.currentUserId = user.uid
                    self.userEmail = user.email ?? self.userEmail
                    self.isAuthenticated = true
                    UserDefaults.standard.set(user.uid, forKey: "saved_user_uid")
                    if let email = user.email {
                        UserDefaults.standard.set(email, forKey: "userEmail")
                    }

                    if let previous, !previous.isEmpty, previous != user.uid {
                        HealthSummaryRepository().reassignSummaries(from: previous, to: user.uid)
                        TaskStore.shared.reassignTasks(from: previous, to: user.uid)
                    }
                } else {
                    // Remote Auth session gone. Keep pure local guest sessions (Keychain guest UID)
                    // so offline bootstrap is not wiped by the initial nil callback. Local stores
                    // are never deleted here.
                    if ProcessInfo.processInfo.arguments.contains("-UITesting") {
                        if let uid = self.currentUserId, !uid.isEmpty {
                            self.isAuthenticated = true
                            return
                        }
                        if let saved = UserDefaults.standard.string(forKey: "saved_user_uid"),
                           !saved.isEmpty {
                            self.currentUserId = saved
                            self.isAuthenticated = true
                            return
                        }
                    }
                    if let guestId = try? GuestLocalIdentity.load(),
                       self.currentUserId == guestId {
                        return
                    }
                    // XCUITest seeds a deterministic uitest-* uid before Auth is ready.
                    if let uid = self.currentUserId, uid.hasPrefix("uitest-") {
                        self.isAuthenticated = true
                        return
                    }
                    if let saved = UserDefaults.standard.string(forKey: "saved_user_uid"),
                       saved.hasPrefix("uitest-") {
                        self.currentUserId = saved
                        self.isAuthenticated = true
                        return
                    }
                    self.clearSessionFlagsPreservingLocalData()
                }
            }
        }
    }

    /// Seeds a local authenticated session for XCUITest without waiting on Firebase Auth.
    public func seedUITestSession(userId: String, email: String) {
        try? GuestLocalIdentity.save(userId)
        currentUserId = userId
        isAuthenticated = true
        userEmail = email
        UserDefaults.standard.set(userId, forKey: "saved_user_uid")
        UserDefaults.standard.set(email, forKey: "userEmail")
    }

    /// Clears in-memory / UserDefaults session markers without wiping local stores.
    private func clearSessionFlagsPreservingLocalData() {
        currentUserId = nil
        isAuthenticated = false
        userEmail = nil
        UserDefaults.standard.removeObject(forKey: "saved_user_uid")
        UserDefaults.standard.removeObject(forKey: "userEmail")
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
    
    /// Sign in anonymously for quick start (no account required).
    public func signInAnonymously() async throws {
        error = nil
        if FirebaseApp.app() != nil {
            let previous = currentUserId ?? (try? GuestLocalIdentity.load())
            do {
                let result = try await Auth.auth().signInAnonymously()
                applyAuthenticatedUser(result.user, previousLocalId: previous)
            } catch {
                self.error = error.localizedDescription
                throw error
            }
            return
        }

        let guestUID = try GuestLocalIdentity.resolvedOrCreate()
        currentUserId = guestUID
        isAuthenticated = true
        userEmail = nil
        UserDefaults.standard.set(guestUID, forKey: "saved_user_uid")
    }
    
    /// Sign in with email/password. Requires Firebase; never invents unstable fallback UIDs.
    public func signIn(email: String, password: String) async throws {
        error = nil
        guard FirebaseApp.app() != nil else {
            throw FirebaseManagerError.firebaseUnavailable
        }
        let previous = currentUserId
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            applyAuthenticatedUser(result.user, previousLocalId: previous)
            UserDefaults.standard.set(email, forKey: "userEmail")
            userEmail = email
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }
    
    /// Create account with email/password. Requires Firebase; never invents unstable fallback UIDs.
    public func createAccount(email: String, password: String) async throws {
        error = nil
        guard FirebaseApp.app() != nil else {
            throw FirebaseManagerError.firebaseUnavailable
        }
        let previous = currentUserId
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            applyAuthenticatedUser(result.user, previousLocalId: previous)
            UserDefaults.standard.set(email, forKey: "userEmail")
            userEmail = email
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }
    
    /// Sign out.
    public func signOut() throws {
        if FirebaseApp.app() != nil {
            try? Auth.auth().signOut()
        }
        clearSessionFlagsPreservingLocalData()
        LicenseManager.shared.clearLocalLicense()
    }

    /// Firebase ID token for Azure auth-proxy calls.
    public func idToken(forceRefresh: Bool = false) async throws -> String? {
        guard FirebaseApp.app() != nil, let user = Auth.auth().currentUser else { return nil }
        return try await user.getIDToken(forcingRefresh: forceRefresh)
    }

    /// Sign in with Apple (AuthenticationServices → Firebase).
    public func signInWithApple() async throws {
        guard FirebaseApp.app() != nil else {
            throw FirebaseManagerError.firebaseUnavailable
        }
        let coordinator = AppleSignInCoordinator()
        let credential = try await coordinator.signIn()
        let result = try await Auth.auth().signIn(with: credential)
        applyAuthenticatedUser(result.user)
        if let fullName = result.user.displayName, !fullName.isEmpty {
            UserDefaults.standard.set(fullName, forKey: "userName")
        }
    }

    /// True when bundled Firebase options are the offline dummy (Google SSO must not run).
    public static var isMockConfiguration: Bool {
        LookAfterFirebaseConfiguration.configureIfNeeded()
        guard let app = FirebaseApp.app() else { return true }
        if mockProjectIDs.contains(app.options.projectID ?? "") { return true }
        if app.options.apiKey == LookAfterFirebaseConfiguration.mockAPIKey { return true }
        let appID = app.options.googleAppID
        return appID.contains("1234567890")
    }

    /// Sign in with Google via native Google Sign-In SDK → Firebase Auth.
    public func signInWithGoogle() async throws {
        guard FirebaseApp.app() != nil else {
            throw FirebaseManagerError.firebaseUnavailable
        }
        guard !Self.isMockConfiguration else {
            throw FirebaseManagerError.ssoFailed(
                "Add your Firebase iOS GoogleService-Info.plist to Config/, then rebuild."
            )
        }
        #if os(iOS)
        let credential = try await GoogleSignInCoordinator.signIn()
        let result = try await Auth.auth().signIn(with: credential)
        applyAuthenticatedUser(result.user)
        if let name = result.user.displayName, !name.isEmpty {
            UserDefaults.standard.set(name, forKey: "userName")
        }
        #else
        throw FirebaseManagerError.ssoFailed("Google Sign-In is available on iOS. Use Apple or email on Mac.")
        #endif
    }

    private func applyAuthenticatedUser(_ user: User, previousLocalId: String? = nil) {
        let previous = previousLocalId ?? currentUserId
        currentUserId = user.uid
        userEmail = user.email ?? userEmail
        isAuthenticated = true
        UserDefaults.standard.set(user.uid, forKey: "saved_user_uid")
        if let email = user.email {
            UserDefaults.standard.set(email, forKey: "userEmail")
        }
        if let previous, !previous.isEmpty, previous != user.uid {
            HealthSummaryRepository().reassignSummaries(from: previous, to: user.uid)
            TaskStore.shared.reassignTasks(from: previous, to: user.uid)
        }
    }

    // MARK: - Firestore Helpers
    
    /// Get a reference to a user's collection.
    public func userCollection(_ collection: String) -> CollectionReference? {
        guard isCloudSyncAvailable, let userId = Auth.auth().currentUser?.uid else { return nil }
        return db?.collection("users").document(userId).collection(collection)
    }
    
    /// Encode a Codable object to Firestore-compatible dictionary.
    public func encode<T: Encodable>(_ item: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(item)
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
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(type, from: jsonData)
    }
}

// MARK: - Errors

public enum FirebaseManagerError: Error, LocalizedError, Equatable {
    case notAuthenticated
    case documentNotFound
    case encodingError
    case collectionNotFound
    case ssoFailed(String)
    case firebaseUnavailable
    
    public var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "User not authenticated"
        case .documentNotFound: return "Document not found"
        case .encodingError: return "Failed to encode data"
        case .collectionNotFound: return "Collection not found"
        case .ssoFailed(let message): return message
        case .firebaseUnavailable: return "Firebase is not configured"
        }
    }
}
