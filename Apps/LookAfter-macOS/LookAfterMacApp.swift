import SwiftUI
import FirebaseCore
import LookAfterCore
import LookAfterData

/// macOS App Entry Point with Menu Bar extra and background window.
@main
struct LookAfterMacApp: App {
    
    init() {
        LookAfterFirebaseConfiguration.configureIfNeeded()
        AuthProxyBootstrap.configureIfNeeded()
    }
    
    var body: some Scene {
        WindowGroup {
            MacContentView()
                .lookAfterThemed()
                .preferredColorScheme(AppAppearanceMode.load().colorScheme)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        
        MenuBarExtra(UserFacingCopy.productName, systemImage: "brain.head.profile") {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(UserFacingCopy.productName) AI Brain")
                    .font(.headline)
                Divider()
                Button("Open \(UserFacingCopy.productName) Dashboard") {
                    NSApp.activate(ignoringOtherApps: true)
                }
                Divider()
                Button("Quit \(UserFacingCopy.productName)") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding()
        }
    }
}
