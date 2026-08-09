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
                    shell: shell,
                    adhdVM: shell.adhdVM
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
            .modifier(ExperienceRootNotificationModifier(shell: shell))
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
            shell.prepareExecutionEnvironmentForBackground()
            BackgroundAnalyticsScheduler.shared.handleAppBackground(userId: userId)
            PostWakeSessionStore.recordBackground()
            BackgroundNotificationRefreshTask.scheduleNextRefresh()
            BehavioralTelemetryBackgroundTask.scheduleNext()
            shell.persistResume(
                userId: userId,
                screen: "briefing",
                experienceMode: nil,
                aiPreview: shell.brain.chatHistory.last?.content
            )
        } else if phase == .active {
            AppForegroundTracker.recordForeground()
            shell.syncExecutionEnvironment()
            let userId = firebase.resolvedUserId
            if !userId.isEmpty {
                Task {
                    await LookAfterIntentBridge.shared.processPendingQueue(userId: userId)
                }
            }
            let healthEnabled = UserDefaults.standard.object(forKey: "enableHealth") as? Bool ?? true
            if healthEnabled, !userId.isEmpty, healthSync.isAvailable {
                healthSync.refreshConnectionStatus(userId: userId, healthSummary: shell.brainVM.healthSummary)
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
                        capacityLLMPolicy: .deterministicOnly
                    )
                }
            }
            .onChange(of: firebase.isAuthenticated) { wasAuthenticated, authenticated in
                guard authenticated else { return }
                showOnboarding = !UserLifeProfileStore.hasCompletedOnboarding
                // Launch while already signed in is handled by `.task` → configureOnLaunch.
                guard !wasAuthenticated else { return }
                shell.bootstrap(userId: firebase.resolvedUserId, healthSync: healthSync)
            }
            .onChange(of: shell.factoryResetGeneration) { _, _ in
                showOnboarding = !UserLifeProfileStore.hasCompletedOnboarding
                AppFeatureTourStore.reset()
            }
            .task { await configureOnLaunch() }
    }
}

private struct ExperienceRootFocusModifier: ViewModifier {
    @ObservedObject var firebase: FirebaseManager
    @ObservedObject var shell: AppShellState
    @ObservedObject var adhdVM: ADHDViewModel

    /// Coalesces rapid focus-state @Published flips into one Live Activity update (PERF-001).
    @State private var focusSyncTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onChange(of: adhdVM.showContextRecovery) { _, show in
                guard show, let task = adhdVM.lastInterruptedTask else { return }
                let userId = firebase.currentUserId ?? ""
                let elapsed = Int(adhdVM.focusSessionElapsed)
                Task { @MainActor in
                    await Task.yield()
                    ResumeEngine.shared.captureFocusSession(
                        task: task,
                        elapsedSeconds: elapsed,
                        userId: userId
                    )
                }
            }
            .onChange(of: adhdVM.isFocusSessionActive) { _, active in
                focusSyncTask?.cancel()
                Task { @MainActor in
                    await Task.yield()
                    ExecutionEnvironmentCoordinator.shared.setManualFocusActive(active)
                    if active {
                        WidgetSyncService.shared.startFocusActivity(adhdVM: adhdVM)
                    } else {
                        LiveActivityManager.shared.endFocusActivity()
                        shell.syncExecutionEnvironment()
                    }
                }
            }
            // Batch pause/break/target/progress into a single deferred sync.
            .onChange(of: adhdVM.isPaused) { _, _ in scheduleCoalescedFocusSync() }
            .onChange(of: adhdVM.isOnBreak) { _, _ in scheduleCoalescedFocusSync() }
            .onChange(of: adhdVM.focusSessionTarget) { _, _ in scheduleCoalescedFocusSync() }
            .onChange(of: adhdVM.focusProgressBucket) { _, _ in scheduleCoalescedFocusSync() }
            .onDisappear { focusSyncTask?.cancel() }
    }

    private func scheduleCoalescedFocusSync() {
        guard adhdVM.isFocusSessionActive else { return }
        focusSyncTask?.cancel()
        focusSyncTask = Task { @MainActor in
            // ~3 frames — collapses pause+break+target churn on session start.
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled, adhdVM.isFocusSessionActive else { return }
            WidgetSyncService.shared.syncFocusActivity(adhdVM: adhdVM)
        }
    }
}

private struct ExperienceRootDataModifier: ViewModifier {
    @ObservedObject var firebase: FirebaseManager
    @ObservedObject var shell: AppShellState
    @ObservedObject var analytics: BackgroundAnalyticsService
    /// Debounce fan-out from `.taskListDidChange` — can fire many times during reconcile (PERF-002).
    @State private var taskListFanoutTask: Task<Void, Never>?
    @State private var scheduleFanoutTask: Task<Void, Never>?

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
                guard !shell.isPerformingFactoryReset else { return }
                let userId = firebase.resolvedUserId
                if !userId.isEmpty {
                    // Cheap path — keep VM in sync immediately.
                    shell.tasksVM.syncFromTaskStore()
                    shell.tasksVM.requestDebouncedScheduleReconcile(userId: userId)
                }
                // Heavy briefing/brain work coalesced.
                taskListFanoutTask?.cancel()
                taskListFanoutTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    guard !Task.isCancelled, !shell.isPerformingFactoryReset else { return }
                    let uid = firebase.resolvedUserId
                    shell.briefingVM.refreshLifeGaps(tasksVM: shell.tasksVM, userId: uid)
                    guard !uid.isEmpty else { return }
                    await shell.brainVM.regenerateCognitiveSnapshot(
                        completedTasksToday: shell.tasksVM.completedToday,
                        userId: uid
                    )
                    let healthEnabled = UserDefaults.standard.object(forKey: "enableHealth") as? Bool ?? true
                    shell.briefingVM.refreshTaskProgress(
                        brainVM: shell.brainVM,
                        tasksVM: shell.tasksVM,
                        healthKitAvailable: healthEnabled,
                        lifeTimelineEvents: shell.timelineService.snapshot.today
                    )
                    shell.syncBrainLiveProgress(userId: uid)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .scheduleDidChange)) { _ in
                guard !shell.isPerformingFactoryReset else { return }
                shell.scheduleAppleCalendarSync()
                scheduleFanoutTask?.cancel()
                scheduleFanoutTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    guard !Task.isCancelled, !shell.isPerformingFactoryReset else { return }
                    let userId = firebase.resolvedUserId
                    shell.refreshWidgetData()
                    guard !userId.isEmpty else { return }
                    let healthEnabled = UserDefaults.standard.object(forKey: "enableHealth") as? Bool ?? true
                    shell.briefingVM.refreshTaskProgress(
                        brainVM: shell.brainVM,
                        tasksVM: shell.tasksVM,
                        healthKitAvailable: healthEnabled,
                        lifeTimelineEvents: shell.timelineService.snapshot.today
                    )
                }
            }
            .onDisappear {
                taskListFanoutTask?.cancel()
                scheduleFanoutTask?.cancel()
            }
    }
}
}

private struct ExperienceRootNotificationModifier: ViewModifier {
    @ObservedObject var shell: AppShellState

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .taskListDidChange)) { _ in
                guard !shell.isPerformingFactoryReset else { return }
                Task { await NotificationCoordinator.shared.refreshFromShell(shell) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .medicationListDidChange)) { _ in
                guard !shell.isPerformingFactoryReset else { return }
                Task { await NotificationCoordinator.shared.refreshFromShell(shell) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .captureDidRoute)) { _ in
                guard !shell.isPerformingFactoryReset else { return }
                shell.refreshWidgetData()
                Task { await NotificationCoordinator.shared.refreshFromShell(shell) }
            }
            .onChange(of: shell.adhdVM.isFocusSessionActive) { _, _ in
                guard !shell.isPerformingFactoryReset else { return }
                Task {
                    if shell.adhdVM.isFocusSessionActive {
                        await NotificationCoordinator.shared.refreshFromShell(shell)
                    } else {
                        await NotificationCoordinator.shared.refreshAfterFocusSessionEnded()
                    }
                }
            }
            .onChange(of: shell.adhdVM.isOnBreak) { _, _ in
                guard !shell.isPerformingFactoryReset, shell.adhdVM.isFocusSessionActive else { return }
                Task { await NotificationCoordinator.shared.refreshFromShell(shell) }
            }
            .onReceive(NotificationCenter.default.publisher(for: ExecutionFocusCoordinator.didChangeNotification)) { _ in
                guard !shell.isPerformingFactoryReset else { return }
                Task { await NotificationCoordinator.shared.refreshFromShell(shell) }
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
            .task(id: "\(firebase.isAuthenticated)-\(showOnboarding)") {
                guard firebase.isAuthenticated, !showOnboarding else { return }
                await presentFeatureTour(.milliseconds(700))
            }
    }
}
