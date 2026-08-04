import SwiftUI
import LookAfterCore
import LookAfterData
import LookAfterFeatures
import LookAfterHealth

/// Root shell — V4 single canvas (Classic + Companion retired).
struct ExperienceRootView: View {
    @EnvironmentObject private var shell: AppShellState
    @StateObject private var firebase = FirebaseManager.shared
    @StateObject private var healthSync = HealthSyncService.shared
    @ObservedObject private var analytics = BackgroundAnalyticsService.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOnboarding = !UserLifeProfileStore.hasCompletedOnboarding
    @StateObject private var featureTour = AppFeatureTourCoordinator()

    var body: some View {
        ZStack {
            PremiumBackground()

            LookAfterMasterCanvas()
                .environmentObject(featureTour)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.25), value: showOnboarding)
        .overlay { onboardingOverlay }
        .accessibilityIdentifier("screen-root")
        .modifier(
            ExperienceRootLifecycleModifier(
                firebase: firebase,
                healthSync: healthSync,
                analytics: analytics,
                featureTour: featureTour,
                showOnboarding: $showOnboarding,
                scenePhase: scenePhase,
                presentFeatureTour: presentFeatureTourIfNeeded
            )
        )
    }

    @ViewBuilder
    private var onboardingOverlay: some View {
        if firebase.isAuthenticated && showOnboarding {
            OnboardingView(
                userId: firebase.resolvedUserId,
                healthSync: healthSync
            ) { sections in
                showOnboarding = false
                let userId = firebase.resolvedUserId
                Task {
                    UserLifeProfileStore.syncUserNameFromProfileIfNeeded()
                    await shell.refreshTasksFromProfile(userId: userId, sections: sections)
                    let healthEnabled = UserDefaults.standard.object(forKey: "enableHealth") as? Bool ?? true
                    if healthEnabled,
                       healthSync.syncPhase != .complete,
                       !healthSync.isConnectingForSetup,
                       !healthSync.isSyncing,
                       !userId.isEmpty {
                        healthSync.connectHealthInBackground(userId: userId)
                    }
                    await presentFeatureTourIfNeeded(after: .milliseconds(700))
                }
            }
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }

    private func presentFeatureTourIfNeeded(after delay: Duration) async {
        guard firebase.isAuthenticated, !showOnboarding, AppFeatureTourStore.shouldPresent else { return }
        try? await Task.sleep(for: delay)
        guard !showOnboarding, !featureTour.isActive else { return }
        featureTour.start()
    }
}
