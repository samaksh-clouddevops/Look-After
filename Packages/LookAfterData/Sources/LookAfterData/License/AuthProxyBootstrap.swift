import Foundation
import LookAfterAI

/// Bootstraps Azure auth-proxy client wiring for Look After.
@MainActor
public enum AuthProxyBootstrap {
    public static func configureIfNeeded(bundle: Bundle = .main) {
        guard let config = AuthProxyConfiguration.fromBundle(bundle) else {
            LicenseManager.shared.configure(proxyClient: nil)
            return
        }
        let client = AuthProxyClient(
            configuration: config,
            tokenProvider: FirebaseAuthProxyTokenProvider()
        )
        LicenseManager.shared.configure(proxyClient: client)
    }
}
