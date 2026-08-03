import SwiftUI
import FirebaseCore
import LifeOSCore

/// macOS App Entry Point with Menu Bar extra and background window.
@main
struct LifeOSMacApp: App {
    
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            MacContentView()
                .preferredColorScheme(.dark)
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
