import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import LifeOSCore

/// Central Firebase manager — handles authentication and Firestore database access.
/// All data flows through this manager for consistent access control.
@MainActor
public final class FirebaseManager: ObservableObject {
    
    @Published public var currentUserId: String?
    @Published public var isAuthenticated: Bool = false
    @Published public var userEmail: String? = UserDefaults.standard.string(forKey: "userEmail")
    @Published public var error: String?
    
    public var db: Firestore? {
        if FirebaseApp.app() == nil {
            if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
               let options = FirebaseOptions(contentsOfFile: path) {
                FirebaseApp.configure(options: options)
            }
        }
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
    
    public static let shared = FirebaseManager()
    
    private init() {
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
                if let user = user {
                    let previous = self?.currentUserId
                    self?.currentUserId = user.uid
                    self?.userEmail = user.email ?? self?.userEmail
                    self?.isAuthenticated = true
                    UserDefaults.standard.set(user.uid, forKey: "saved_user_uid")

                    if let previous, !previous.isEmpty, previous != user.uid {
                        HealthSummaryRepository().reassignSummaries(from: previous, to: user.uid)
                    }
                }
            }
        }
    }

    /// Stable account id for local storage — prefers Firebase Auth UID.
    public var resolvedUserId: String {
        if let uid = Auth.auth().currentUser?.uid, !uid.isEmpty { return uid }
        if let uid = currentUserId, !uid.isEmpty { return uid }
        return UserDefaults.standard.string(forKey: "saved_user_uid") ?? ""
    }
    
    /// Sign in anonymously for quick start (no account required).
    public func signInAnonymously() async throws {
        let fallbackUid = UserDefaults.standard.string(forKey: "saved_user_uid") ?? "guest_\(UUID().uuidString.prefix(8))"
        UserDefaults.standard.set(fallbackUid, forKey: "saved_user_uid")
        self.currentUserId = fallbackUid
        self.isAuthenticated = true
        
        if FirebaseApp.app() != nil {
            Task.detached {
                if let result = try? await Auth.auth().signInAnonymously() {
                    await MainActor.run {
                        let previous = FirebaseManager.shared.currentUserId
                        FirebaseManager.shared.currentUserId = result.user.uid
                        UserDefaults.standard.set(result.user.uid, forKey: "saved_user_uid")
                        if let previous, !previous.isEmpty, previous != result.user.uid {
                            HealthSummaryRepository().reassignSummaries(from: previous, to: result.user.uid)
                        }
                    }
                }
            }
        }
    }
    
    /// Sign in with email/password.
    public func signIn(email: String, password: String) async throws {
        let emailHash = abs(email.hashValue)
        let fallbackUid = "usr_\(emailHash)"
        UserDefaults.standard.set(fallbackUid, forKey: "saved_user_uid")
        UserDefaults.standard.set(email, forKey: "userEmail")
        
        self.userEmail = email
        self.currentUserId = fallbackUid
        self.isAuthenticated = true
        
        if FirebaseApp.app() != nil {
            Task.detached {
                if let result = try? await Auth.auth().signIn(withEmail: email, password: password) {
                    await MainActor.run {
                        let previous = FirebaseManager.shared.currentUserId
                        FirebaseManager.shared.currentUserId = result.user.uid
                        UserDefaults.standard.set(result.user.uid, forKey: "saved_user_uid")
                        if let previous, !previous.isEmpty, previous != result.user.uid {
                            HealthSummaryRepository().reassignSummaries(from: previous, to: result.user.uid)
                        }
                    }
                }
            }
        }
    }
    
    /// Create account with email/password.
    public func createAccount(email: String, password: String) async throws {
        let emailHash = abs(email.hashValue)
        let fallbackUid = "usr_\(emailHash)"
        UserDefaults.standard.set(fallbackUid, forKey: "saved_user_uid")
        UserDefaults.standard.set(email, forKey: "userEmail")
        
        self.userEmail = email
        self.currentUserId = fallbackUid
        self.isAuthenticated = true
        
        if FirebaseApp.app() != nil {
            Task.detached {
                if let result = try? await Auth.auth().createUser(withEmail: email, password: password) {
                    await MainActor.run {
                        let previous = FirebaseManager.shared.currentUserId
                        FirebaseManager.shared.currentUserId = result.user.uid
                        UserDefaults.standard.set(result.user.uid, forKey: "saved_user_uid")
                        if let previous, !previous.isEmpty, previous != result.user.uid {
                            HealthSummaryRepository().reassignSummaries(from: previous, to: result.user.uid)
                        }
                    }
                }
            }
        }
    }
    
    /// Sign out.
    public func signOut() throws {
        if FirebaseApp.app() != nil {
            try? Auth.auth().signOut()
        }
        currentUserId = nil
        isAuthenticated = false
        userEmail = nil
        UserDefaults.standard.removeObject(forKey: "saved_user_uid")
        UserDefaults.standard.removeObject(forKey: "userEmail")
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

public enum FirebaseManagerError: Error, LocalizedError {
    case notAuthenticated
    case documentNotFound
    case encodingError
    case collectionNotFound
    
    public var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "User not authenticated"
        case .documentNotFound: return "Document not found"
        case .encodingError: return "Failed to encode data"
        case .collectionNotFound: return "Collection not found"
        }
    }
}
