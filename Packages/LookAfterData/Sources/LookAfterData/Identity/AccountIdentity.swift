import Foundation
import FirebaseCore

/// Canonical user identity for reads and writes across the app.
@MainActor
public final class AccountIdentity: ObservableObject {
    public static let shared = AccountIdentity()

    @Published public private(set) var canonicalUserId: String = ""

    private let firebase: FirebaseManager

    public init(firebase: FirebaseManager? = nil) {
        LookAfterFirebaseConfiguration.configureIfNeeded()
        self.firebase = firebase ?? FirebaseManager.shared
        refresh()
    }

    public func refresh() {
        guard FirebaseApp.app() != nil else {
            canonicalUserId = UserDefaults.standard.string(forKey: "saved_user_uid") ?? ""
            return
        }
        canonicalUserId = firebase.resolvedUserId
    }

    public func resolved(_ fallback: String = "") -> String {
        if !canonicalUserId.isEmpty { return canonicalUserId }
        if !fallback.isEmpty { return fallback }
        guard FirebaseApp.app() != nil else {
            return UserDefaults.standard.string(forKey: "saved_user_uid") ?? ""
        }
        return firebase.resolvedUserId
    }
}
