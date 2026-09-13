import SwiftUI
import FirebaseCore
import LookAfterData
import LookAfterAI

/// Runs before `@main` when this translation unit loads.
private enum AppLaunchFirebaseBootstrap {
    static let activated: Void = {
        LookAfterFirebaseConfiguration.configureIfNeeded()
    }()
}
private let appLaunchFirebaseBootstrap: Void = AppLaunchFirebaseBootstrap.activated

/// LifeOS App Entry Point
@main
struct LookAfterApp: App {
    @UIApplicationDelegateAdaptor(LookAfterAppDelegate.self) private var appDelegate

    init() {
        LookAfterFirebaseConfiguration.configureIfNeeded()
        AuthProxyBootstrap.configureIfNeeded()
        UITestLaunchConfiguration.applyIfNeeded()
#if DEBUG
        // Developer convenience only: prefer direct z.ai / OpenAI keys from
        // ~/ADHD/credentials or env vars on every launch. Gated to DEBUG so it can
        // never silently overwrite a Release user's own configured default key.
        // Moved off the launch-blocking path: this chains several synchronous Keychain
        // round-trips + a filesystem read, which previously delayed time-to-first-frame
        // on every cold launch. Deferring to a background task after init() lets
        // WindowGroup/ContentView render first.
        Task.detached(priority: .utility) {
            _ = GLMKeyManager.shared.syncDeveloperCredentials()
            _ = GLMKeyManager.shared.syncOpenAIDeveloperCredentials()
        }
#endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
