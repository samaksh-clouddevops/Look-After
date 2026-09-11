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
        // Prefer direct z.ai / OpenAI keys — sync from ~/ADHD/credentials on every launch.
        _ = GLMKeyManager.shared.syncDeveloperCredentials()
        _ = GLMKeyManager.shared.syncOpenAIDeveloperCredentials()
        UITestLaunchConfiguration.applyIfNeeded()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
