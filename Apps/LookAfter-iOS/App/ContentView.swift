import SwiftUI
import LookAfterCore
import LookAfterAI
import LookAfterData
import LookAfterFeatures

/// Root entry — Classic and AI Executive modes share one data shell.
struct ContentView: View {
    @StateObject private var shell = AppShellState()
    @StateObject private var experience = ExperienceModeController()

    var body: some View {
        ExperienceRootView()
            .environmentObject(shell)
            .environmentObject(experience)
            .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
