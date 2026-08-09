import Foundation
import FirebaseAuth
import FirebaseCore
import LookAfterAI

/// Adapts Firebase Auth ID tokens for `AuthProxyClient`.
public struct FirebaseAuthProxyTokenProvider: AuthProxyTokenProviding {
    private static let mockProjectIDs: Set<String> = ["lifeos-mock", "lifeos-dummy"]

    public init() {}

    public func idToken(forceRefresh: Bool) async throws -> String? {
        // Bundled mock Firebase cannot mint verifiable ID tokens. The auth proxy accepts
        // Bearer dev:<uid> when AUTH_DEV_ALLOW_INSECURE=true (current Azure deploy).
        if Self.usesMockFirebaseProject {
            let uid = await MainActor.run { FirebaseManager.shared.resolvedUserId }
            guard !uid.isEmpty else { return nil }
            return "dev:\(uid)"
        }

        guard let user = Auth.auth().currentUser else { return nil }
        return try await user.getIDToken(forcingRefresh: forceRefresh)
    }

    private static var usesMockFirebaseProject: Bool {
        guard let projectID = FirebaseApp.app()?.options.projectID else { return true }
        return mockProjectIDs.contains(projectID)
    }
}
