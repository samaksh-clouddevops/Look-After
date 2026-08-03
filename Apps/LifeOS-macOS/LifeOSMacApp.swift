import SwiftUI
import FirebaseCore

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
        
        MenuBarExtra("ADHD Bitch", systemImage: "brain.head.profile") {
            VStack(alignment: .leading, spacing: 8) {
                Text("LifeOS AI Brain")
                    .font(.headline)
                Divider()
                Button("Open LifeOS Dashboard") {
                    NSApp.activate(ignoringOtherApps: true)
                }
                Divider()
                Button("Quit LifeOS") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding()
        }
    }
}
