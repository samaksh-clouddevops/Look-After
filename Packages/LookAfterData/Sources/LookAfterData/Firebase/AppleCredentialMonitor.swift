import Foundation
import AuthenticationServices
import FirebaseAuth

/// Watches Sign in with Apple credential state. On revoke/transfer, clears Firebase session
/// flags without deleting local user data.
@MainActor
public enum AppleCredentialMonitor {
    private static var observer: NSObjectProtocol?
    private static var started = false

    public static func startIfNeeded() {
        guard !started else { return }
        started = true

        observer = NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                handleRevocation()
            }
        }

        Task { await refreshCredentialState() }
    }

    public static func refreshCredentialState() async {
        guard let user = Auth.auth().currentUser else { return }
        let appleProvider = user.providerData.first { $0.providerID == "apple.com" }
        guard let appleUserID = appleProvider?.uid, !appleUserID.isEmpty else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: appleUserID) { state, _ in
                Task { @MainActor in
                    switch state {
                    case .revoked, .transferred:
                        handleRevocation()
                    case .authorized, .notFound:
                        break
                    @unknown default:
                        break
                    }
                    continuation.resume()
                }
            }
        }
    }

    private static func handleRevocation() {
        // Clear remote session; keep on-disk local stores (same policy as Firebase nil listener).
        try? FirebaseManager.shared.signOut()
    }
}
