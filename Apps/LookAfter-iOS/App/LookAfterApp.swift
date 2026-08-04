import SwiftUI
import FirebaseCore
import LookAfterData

/// LifeOS App Entry Point
@main
struct LookAfterApp: App {
    @UIApplicationDelegateAdaptor(LookAfterAppDelegate.self) private var appDelegate

    init() {
        LookAfterFirebaseConfiguration.configureIfNeeded()
        UITestLaunchConfiguration.applyIfNeeded()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
