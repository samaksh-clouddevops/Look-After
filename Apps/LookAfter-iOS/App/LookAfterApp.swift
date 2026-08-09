import SwiftUI
import FirebaseCore
import LookAfterData

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
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
