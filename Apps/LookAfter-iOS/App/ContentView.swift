import SwiftUI
import LookAfterCore
import LookAfterAI
import LookAfterData
import LookAfterFeatures

/// Root entry — V4 single shell.
struct ContentView: View {
    @StateObject private var shell = AppShellState()
    @AppStorage(AppAppearanceMode.storageKey) private var appearanceRaw = AppAppearanceMode.system.rawValue

    private var appearance: AppAppearanceMode {
        AppAppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    var body: some View {
        ExperienceRootView()
            .environmentObject(shell)
            .lookAfterThemed()
            .preferredColorScheme(appearance.colorScheme)
    }
}

#Preview {
    ContentView()
}
