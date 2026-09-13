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
        // Prefer direct z.ai / OpenAI keys — sync from ~/ADHD/credentials on every launch.
        // Moved off the launch-blocking path: this chains several synchronous Keychain
        // round-trips + a filesystem read, which previously delayed time-to-first-frame
        // on every cold launch. Deferring to a background task after init() lets
        // WindowGroup/ContentView render first.
        Task.detached(priority: .utility) {
            _ = GLMKeyManager.shared.syncDeveloperCredentials()
            _ = GLMKeyManager.shared.syncOpenAIDeveloperCredentials()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
