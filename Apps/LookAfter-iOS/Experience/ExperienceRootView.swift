import SwiftUI
import LookAfterCore
import LookAfterData
import LookAfterFeatures
import LookAfterHealth

/// Root switcher — Classic and AI Executive share `AppShellState` (same data).
struct ExperienceRootView: View {
    @EnvironmentObject private var shell: AppShellState
    @EnvironmentObject private var experience: ExperienceModeController
    @StateObject private var firebase = FirebaseManager.shared
    @StateObject private var healthSync = HealthSyncService.shared
    @ObservedObject private var analytics = BackgroundAnalyticsService.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOnboarding = !UserLifeProfileStore.hasCompletedOnboarding

    var body: some View {
        ZStack {
            PremiumBackground()

            Group {
                switch experience.mode {
                case .classic:
                    LookAfterMasterCanvas()
                case .aiExecutive:
                    AIExecutiveCanvas()
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.98)),
                removal: .opacity.combined(with: .scale(scale: 1.02))
            ))
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: experience.mode)
        .environment(\.experienceMode, experience.mode)
        .overlay {
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
                    }
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showOnboarding)
        .onChange(of: healthSync.syncPhase) { _, phase in
            guard phase == .complete, firebase.isAuthenticated else { return }
            let userId = firebase.resolvedUserId
            guard !userId.isEmpty else { return }
            Task {
                await shell.refreshContext(
                    userId: userId,
                    userName: UserLifeProfileStore.resolvedDisplayName(),
                    peakStartHour: UserLifeProfileStore.load().peakStartHour
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
                    peakStartHour: UserLifeProfileStore.load().peakStartHour
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
        .task {
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
        .onChange(of: shell.tasksVM.completedToday.count) { oldCount, newCount in
            guard newCount > oldCount, let task = shell.tasksVM.completedToday.last else { return }
            let userId = firebase.currentUserId ?? ""
            Task {
                await shell.brainVM.handleTaskCompleted(task, userId: userId)
                shell.refreshWidgetData()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard firebase.isAuthenticated else { return }
            let userId = firebase.currentUserId ?? ""
            if phase == .background {
                BackgroundAnalyticsScheduler.shared.handleAppBackground(userId: userId)
                PostWakeSessionStore.recordBackground()
                shell.persistResume(
                    userId: userId,
                    screen: experience.mode == .aiExecutive ? "today" : "classic",
                    experienceMode: experience.mode,
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
        .onChange(of: shell.adhdVM.showContextRecovery) { _, show in
            guard show, let task = shell.adhdVM.lastInterruptedTask else { return }
            let userId = firebase.currentUserId ?? ""
            ResumeEngine.shared.captureFocusSession(
                task: task,
                elapsedSeconds: Int(shell.adhdVM.focusSessionElapsed),
                userId: userId
            )
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
        .onChange(of: shell.adhdVM.isFocusSessionActive) { _, active in
            if active {
                WidgetSyncService.shared.startFocusActivity(adhdVM: shell.adhdVM)
            } else {
                LiveActivityManager.shared.endFocusActivity()
            }
        }
        .onChange(of: shell.adhdVM.isPaused) { _, _ in
            WidgetSyncService.shared.syncFocusActivity(adhdVM: shell.adhdVM)
        }
        .onChange(of: shell.adhdVM.isOnBreak) { _, _ in
            WidgetSyncService.shared.syncFocusActivity(adhdVM: shell.adhdVM)
        }
        .onChange(of: shell.adhdVM.focusSessionTarget) { _, _ in
            WidgetSyncService.shared.syncFocusActivity(adhdVM: shell.adhdVM)
        }
    }
}
