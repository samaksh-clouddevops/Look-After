import SwiftUI
import LookAfterCore
import LookAfterData
import LookAfterFeatures
import LookAfterHealth

struct ExperienceRootLifecycleModifier: ViewModifier {
    @EnvironmentObject private var shell: AppShellState
    @ObservedObject var firebase: FirebaseManager
    @ObservedObject var healthSync: HealthSyncService
    @ObservedObject var analytics: BackgroundAnalyticsService
    @ObservedObject var featureTour: AppFeatureTourCoordinator
    @Binding var showOnboarding: Bool
    let scenePhase: ScenePhase
    let presentFeatureTour: (_ delay: Duration) async -> Void

    func body(content: Content) -> some View {
        content
            .modifier(
                ExperienceRootSyncModifier(
                    firebase: firebase,
                    healthSync: healthSync,
                    showOnboarding: $showOnboarding,
                    configureOnLaunch: configureOnLaunch
                )
            )
            .modifier(
                ExperienceRootFocusModifier(
                    firebase: firebase,
                    shell: shell
                )
            )
            .modifier(
                ExperienceRootDataModifier(
                    firebase: firebase,
                    shell: shell,
                    analytics: analytics
                )
            )
            .modifier(
                ExperienceRootTourModifier(
                    firebase: firebase,
                    featureTour: featureTour,
                    showOnboarding: $showOnboarding,
                    presentFeatureTour: presentFeatureTour
                )
            )
            .onChange(of: scenePhase) { _, phase in
                handleScenePhaseChange(phase)
            }
    }

    private func configureOnLaunch() async {
        guard firebase.isAuthenticated else { return }
        let userId = firebase.resolvedUserId
        if UserDefaults.standard.object(forKey: "enableHealth") as? Bool ?? true {
            healthSync.startHealthObservers()
        }
        shell.adhdVM.onFocusSessionEnded = { minutes, _ in
            Task {
                await shell.brainVM.handleFlowSessionEnded(durationMinutes: minutes, userId: userId)
                shell.refreshWidgetData()
            }
        }
        shell.bootstrap(userId: userId, healthSync: healthSync)
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        guard firebase.isAuthenticated else { return }
        let userId = firebase.currentUserId ?? ""
        if phase == .background {
            BackgroundAnalyticsScheduler.shared.handleAppBackground(userId: userId)
            PostWakeSessionStore.recordBackground()
            shell.persistResume(
                userId: userId,
                screen: "briefing",
                experienceMode: nil,
                aiPreview: shell.brain.chatHistory.last?.content
            )
        } else if phase == .active {
            let healthEnabled = UserDefaults.standard.object(forKey: "enableHealth") as? Bool ?? true
            if healthEnabled, !userId.isEmpty, healthSync.isAvailable {
                Task {
                    await healthSync.ensureSynced(userId: userId, maxAgeSeconds: 15 * 60)
                }
            }
        }
    }
}

private struct ExperienceRootSyncModifier: ViewModifier {
    @EnvironmentObject private var shell: AppShellState
    @ObservedObject var firebase: FirebaseManager
    @ObservedObject var healthSync: HealthSyncService
    @Binding var showOnboarding: Bool
    let configureOnLaunch: () async -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: healthSync.syncPhase) { _, phase in
                guard phase == .complete, firebase.isAuthenticated else { return }
                let userId = firebase.resolvedUserId
                guard !userId.isEmpty else { return }
                Task {
                    await shell.refreshContext(
                        userId: userId,
                        userName: UserLifeProfileStore.resolvedDisplayName(),
                        peakStartHour: UserLifeProfileStore.load().peakStartHour,
                        capacityLLMPolicy: .llmIfDue
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .healthKitDataDidChange)) { _ in
                guard firebase.isAuthenticated, !shell.isPerformingFactoryReset else { return }
                let userId = firebase.resolvedUserId
                guard !userId.isEmpty else { return }
                healthSync.scheduleObserverSync(userId: userId)
                Task {
                    await shell.refreshContext(
                        userId: userId,
                        userName: UserLifeProfileStore.resolvedDisplayName(),
                        peakStartHour: UserLifeProfileStore.load().peakStartHour,
                        capacityLLMPolicy: .llmIfDue
                    )
                }
            }
            .onChange(of: firebase.isAuthenticated) { _, authenticated in
                guard authenticated else { return }
                showOnboarding = !UserLifeProfileStore.hasCompletedOnboarding
                shell.bootstrap(userId: firebase.resolvedUserId, healthSync: healthSync)
            }
            .onChange(of: shell.factoryResetGeneration) { _, _ in
                showOnboarding = !UserLifeProfileStore.hasCompletedOnboarding
            }
            .task { await configureOnLaunch() }
    }
}

private struct ExperienceRootFocusModifier: ViewModifier {
    @ObservedObject var firebase: FirebaseManager
    @ObservedObject var shell: AppShellState

    func body(content: Content) -> some View {
        content
            .onChange(of: shell.adhdVM.showContextRecovery) { _, show in
                guard show, let task = shell.adhdVM.lastInterruptedTask else { return }
                let userId = firebase.currentUserId ?? ""
                let elapsed = Int(shell.adhdVM.focusSessionElapsed)
                Task { @MainActor in
                    await Task.yield()
                    ResumeEngine.shared.captureFocusSession(
                        task: task,
                        elapsedSeconds: elapsed,
                        userId: userId
                    )
                }
            }
            .onChange(of: shell.adhdVM.isFocusSessionActive) { _, active in
                Task { @MainActor in
                    await Task.yield()
                    if active {
                        WidgetSyncService.shared.startFocusActivity(adhdVM: shell.adhdVM)
                    } else {
                        LiveActivityManager.shared.endFocusActivity()
                    }
                }
            }
            .onChange(of: shell.adhdVM.isPaused) { _, _ in
                Task { @MainActor in
                    await Task.yield()
                    WidgetSyncService.shared.syncFocusActivity(adhdVM: shell.adhdVM)
                }
            }
            .onChange(of: shell.adhdVM.isOnBreak) { _, _ in
                Task { @MainActor in
                    await Task.yield()
                    WidgetSyncService.shared.syncFocusActivity(adhdVM: shell.adhdVM)
                }
            }
            .onChange(of: shell.adhdVM.focusSessionTarget) { _, _ in
                Task { @MainActor in
                    await Task.yield()
                    WidgetSyncService.shared.syncFocusActivity(adhdVM: shell.adhdVM)
                }
            }
    }
}

private struct ExperienceRootDataModifier: ViewModifier {
    @ObservedObject var firebase: FirebaseManager
    @ObservedObject var shell: AppShellState
    @ObservedObject var analytics: BackgroundAnalyticsService

    func body(content: Content) -> some View {
        content
            .onChange(of: shell.tasksVM.completedToday.count) { oldCount, newCount in
                guard newCount > oldCount, let task = shell.tasksVM.completedToday.last else { return }
                let userId = firebase.currentUserId ?? ""
                Task {
                    await shell.brainVM.handleTaskCompleted(task, userId: userId)
                    shell.refreshWidgetData()
                }
            }
            .onChange(of: analytics.lastRefreshAt) { _, _ in
                guard firebase.isAuthenticated, !shell.isPerformingFactoryReset else { return }
                if let aiContext = analytics.cachedAIContext(userId: firebase.currentUserId ?? "") {
                    shell.brain.personalizationContext = UserCalibrationStore.combinedPersonalizationBlock(
                        analyticsBlock: aiContext.promptBlock
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .taskListDidChange)) { _ in
                let userId = firebase.currentUserId ?? ""
                guard !userId.isEmpty, !shell.isPerformingFactoryReset else { return }
                shell.tasksVM.refreshFromLocal(userId: userId)
                shell.refreshWidgetData()
            }
    }
}

private struct ExperienceRootTourModifier: ViewModifier {
    @ObservedObject var firebase: FirebaseManager
    @ObservedObject var featureTour: AppFeatureTourCoordinator
    @Binding var showOnboarding: Bool
    let presentFeatureTour: (_ delay: Duration) async -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .replayAppFeatureTour)) { _ in
                featureTour.start(force: true)
            }
            .onChange(of: showOnboarding) { _, isShowing in
                guard !isShowing, firebase.isAuthenticated else { return }
                Task { await presentFeatureTour(.milliseconds(900)) }
            }
    }
}
