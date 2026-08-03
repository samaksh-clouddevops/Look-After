import SwiftUI
import FirebaseCore

/// LifeOS App Entry Point
@main
struct LifeOSApp: App {
    
    init() {
        // Configure Firebase safely without GoogleService-Info.plist for UI preview
        let options = FirebaseOptions(googleAppID: "1:1234567890:ios:321abc", gcmSenderID: "1234567890")
        options.projectID = "lifeos-mock"
        options.apiKey = "mock-api-key"
        FirebaseApp.configure(options: options)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
