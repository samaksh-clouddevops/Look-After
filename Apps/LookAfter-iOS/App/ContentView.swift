import SwiftUI
import LookAfterCore
import LookAfterAI
import LookAfterData
import LookAfterFeatures

/// Root entry — V4 single shell.
struct ContentView: View {
    @StateObject private var shell = AppShellState()

    var body: some View {
        ExperienceRootView()
            .environmentObject(shell)
            .lookAfterThemed()
    }
}

#Preview {
    ContentView()
}
