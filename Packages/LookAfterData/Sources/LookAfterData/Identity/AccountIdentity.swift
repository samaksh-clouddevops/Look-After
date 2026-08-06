import Foundation

/// Canonical user identity for reads and writes across the app.
@MainActor
public final class AccountIdentity: ObservableObject {
    public static let shared = AccountIdentity()

    @Published public private(set) var canonicalUserId: String = ""

    private let firebase: FirebaseManager

    public init(firebase: FirebaseManager? = nil) {
        self.firebase = firebase ?? FirebaseManager.shared
        refresh()
    }

    public func refresh() {
        canonicalUserId = firebase.resolvedUserId
    }

    public func resolved(_ fallback: String = "") -> String {
        if !canonicalUserId.isEmpty { return canonicalUserId }
        if !fallback.isEmpty { return fallback }
        return firebase.resolvedUserId
    }
}
