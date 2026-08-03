import SwiftUI
import LifeOSCore
import LifeOSAI
import LifeOSData
import LifeOSFeatures

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
