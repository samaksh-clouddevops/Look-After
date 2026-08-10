import Foundation
import os
import LookAfterCore
import LookAfterAI
import LookAfterData
import LookAfterFeatures
import LookAfterHealth

/// Shared view models and brain — identical data for Classic and AI Executive shells.
@MainActor
final class AppShellState: ObservableObject {
    let brain: ExecutiveBrain
    let brainVM: BrainViewModel
    let taskStore: TaskStore
    let timelineService: TimelineService
    let healthStore: HealthStore
    let accountIdentity: AccountIdentity
    let tasksVM: TasksViewModel
    let modulesVM: LifeModulesViewModel
    let adhdVM: ADHDViewModel
    let briefingVM: DailyBriefingViewModel
    let inboxVM: InboxViewModel
    let contextOrchestrator: ContextOrchestrator
    let continueSession: ContinueSessionController
    /// Identity façade (Phase 1). Always available; SessionContainer is optional until flag on.
    let identityService: IdentityService
    /// Set when `ArchitectureFeatureFlags.useSessionContainer` and identity is stable.
    private(set) var session: SessionContainer?

    /// Incremented after factory reset so child views can wipe local @StateObject state.
    @Published private(set) var factoryResetGeneration = 0
    @Published private(set) var isPerformingFactoryReset = false
    @Published private(set) var isBootstrappingFreshStart = false
    @Published var showManualSleepSheet = false
    @Published private(set) var proactiveActions: [ProactiveAction] = []
    @Published private(set) var pendingCalendarChange: CalendarChangeResult?
    @Published var pendingInitiationScript: InitiationScript?
    @Published var showInitiationScriptSheet = false

    private var deferralRecoveryObserver: NSObjectProtocol?
    private var taskCompletedObserver: NSObjectProtocol?
    private var flowDirector: FlowDirector?
    private var flowDirectorUserName: String = ""
    private let calendarSyncService = CalendarSyncService()
    private var calendarSyncDebounceTask: Task<Void, Never>?
    private let bootstrapCoordinator = BootstrapCoordinator()

    init() {
        let glm = GLMService.shared
        let executiveBrain = ExecutiveBrain(glmService: glm)
        let taskStore = TaskStore.shared
        let timelineService = TimelineService.shared
        let healthStore = HealthStore.shared
        let accountIdentity = AccountIdentity.shared
        let identityService = IdentityService.shared
        self.taskStore = taskStore
        self.timelineService = timelineService
        self.healthStore = healthStore
        self.accountIdentity = accountIdentity
        self.identityService = identityService
        brain = executiveBrain
        let sessionFacade = BrainFacadeRouter(primary: DeterministicBrainFacadeBackend())
        brainVM = BrainViewModel(
            brain: executiveBrain,
            taskStore: taskStore,
            healthStore: healthStore,
            brainFacade: sessionFacade
        )
        tasksVM = TasksViewModel(taskStore: taskStore, decomposer: TaskDecomposer(glmService: glm))
        modulesVM = LifeModulesViewModel()
        adhdVM = ADHDViewModel()
        briefingVM = DailyBriefingViewModel()
        inboxVM = InboxViewModel(glmService: glm)
        contextOrchestrator = ContextOrchestrator(glmService: glm)
        continueSession = ContinueSessionController()
        identityService.refreshFromFirebase()
        session = SessionContainer.makeIfReady(identity: identityService, taskStore: taskStore)
        if let session {
            brainVM.configure(brainFacade: session.brainFacade)
        }
        bootstrapCoordinator.executor = self

        adhdVM.onFocusSessionDidStart = { [weak self] in
            guard let self else { return }
            ExecutionEnvironmentCoordinator.shared.setManualFocusActive(true)
            WidgetSyncService.shared.startFocusActivity(adhdVM: self.adhdVM)
        }

        deferralRecoveryObserver = NotificationCenter.default.addObserver(
            forName: .deferralRecoveryScriptReady,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let script = DeferralRecoveryScriptStore.pending else { return }
                self.pendingInitiationScript = script
                self.showInitiationScriptSheet = true
                let action = DeferralRecoveryCoordinator.shared.proactiveAction(from: script)
                self.proactiveActions = [action] + self.proactiveActions.filter { $0.kind != .deferralRecovery }
            }
        }

        taskCompletedObserver = NotificationCenter.default.addObserver(
            forName: .analyticsDataDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let reason = notification.userInfo?["reason"] as? String,
                  reason == AnalyticsDataChangeReason.taskCompleted.rawValue else { return }
            Task { @MainActor in
                await self?.handleTaskCompletedForProactive()
            }
        }
    }

    deinit {
        if let deferralRecoveryObserver {
            NotificationCenter.default.removeObserver(deferralRecoveryObserver)
        }
        if let taskCompletedObserver {
            NotificationCenter.default.removeObserver(taskCompletedObserver)
        }
        calendarSyncDebounceTask?.cancel()
    }

    func removeProactiveAction(_ action: ProactiveAction) {
        proactiveActions.removeAll { $0.id == action.id }
        briefingVM.setProactiveActions(proactiveActions)
        ProactiveSnapshotStore.save(proactiveActions)
    }

    private func handleTaskCompletedForProactive() async {
        let completedCount = briefingVM.progress.completedCount
        let nextTask = tasksVM.tasks.first(where: { $0.status.isActive })
        let momentum = PostCompletionAgent.evaluate(
            completedTodayCount: completedCount,
            nextTask: nextTask
        )
        guard !momentum.isEmpty else { return }
        proactiveActions = momentum + proactiveActions.filter { $0.kind != .postCompletionMomentum }
        briefingVM.setProactiveActions(proactiveActions)
        ProactiveSnapshotStore.save(proactiveActions)
        await NotificationCoordinator.shared.refreshFromShell(self)
    }

    func recordTaskDeferral(_ task: LifeTask) async {
        if let script = await DeferralRecoveryCoordinator.shared.handleDeferral(task: task) {
            pendingInitiationScript = script
            showInitiationScriptSheet = true
            let action = DeferralRecoveryCoordinator.shared.proactiveAction(from: script)
            proactiveActions = [action] + proactiveActions.filter { $0.kind != .deferralRecovery }
        }
    }

    func bootstrap(userId: String, healthSync: HealthSyncService) {
        bootstrapCoordinator.bootstrap(
            userId: userId,
            healthSync: healthSync,
            identity: identityService
        )
    }

    /// True after successful bootstrap (delegates to coordinator).
    var hasCompletedBootstrap: Bool { bootstrapCoordinator.hasCompletedBootstrap }

    func attachSessionIfNeeded() {
        guard ArchitectureFeatureFlags.useSessionContainer else {
            session?.tearDown()
            session = nil
            return
        }
        if let session, !session.isTornDown, !session.isIdentityStale {
            return
        }
        session?.tearDown()
        session = SessionContainer.makeIfReady(
            identity: identityService,
            taskStore: taskStore,
            requireFlag: true
        )
        if let session, let director = flowDirector {
            brainVM.configure(brainFacade: FlowAwareBrainFacade(director: director))
            // Keep session façade in sync when possible.
        } else if let session {
            brainVM.configure(brainFacade: session.brainFacade)
        }
    }

    private func shouldAbortBootstrap(identityGeneration: UInt64) -> Bool {
        guard ArchitectureFeatureFlags.useSessionContainer else { return false }
        if Task.isCancelled { return true }
        if identityService.generation != identityGeneration { return true }
        if let session, session.isIdentityStale { return true }
        return false
    }

    func runBootstrapWork(
        userId: String,
        healthSync: HealthSyncService,
        identityGeneration: UInt64
    ) async {
        if ArchitectureFeatureFlags.useSessionContainer {
            guard identityService.state.isStableForBootstrap else { return }
            guard identityService.generation == identityGeneration else { return }
        }

        // Phase 2: attach Firestore transport and drain outbox when enabled.
        if ArchitectureFeatureFlags.useSyncOutbox {
            SyncOutboxWorker.shared.setTransport(FirestoreSyncOutboxTransport())
            SyncOutboxWorker.shared.scheduleDrain(userId: userId)
        }

        BackgroundAnalyticsScheduler.shared.start(userId: userId)

        if let aiContext = BackgroundAnalyticsService.shared.cachedAIContext(userId: userId) {
            brain.personalizationContext = UserCalibrationStore.combinedPersonalizationBlock(
                analyticsBlock: aiContext.promptBlock
            )
        }

        inboxVM.onCreateTask = { [weak self] draft in
            guard let self else { return }
            _ = try await self.tasksVM.createFromInbox(draft, userId: userId)
        }

        configureCaptureRouter(userId: userId)
        LookAfterIntentBridge.shared.register(shell: self, userId: userId)

        if healthSync.isHealthEnabled {
            healthSync.startHealthObservers()
        }

        await ensureFlowDirector()

        if UserLifeProfileStore.hasCompletedOnboarding, healthSync.isHealthEnabled {
            HealthSummaryRepository().migrateAllSummariesToCanonicalUserId()
            await healthSync.ensureSynced(userId: userId)
        }

        guard !shouldAbortBootstrap(identityGeneration: identityGeneration) else { return }

        async let brainLoad: Void = orchestrateBrain(userId: userId)
        async let taskLoad: Void = tasksVM.loadTasks(userId: userId)
        async let moduleLoad: Void = modulesVM.loadAllData(userId: userId)
        async let inboxLoad: Void = inboxVM.loadItems(userId: userId)
        _ = await (brainLoad, taskLoad, moduleLoad, inboxLoad)

        guard !shouldAbortBootstrap(identityGeneration: identityGeneration) else { return }

        await LookAfterIntentBridge.shared.processPendingQueue(userId: userId)
        await compileLifeModelIfNeeded()
        if let lifeModel = LifeModelStore.load(), lifeModel.hasContent {
            await tasksVM.dedupeLifeCommitmentTasks(userId: userId, model: lifeModel)
            await tasksVM.ensureLifeCommitmentTasks(userId: userId, model: lifeModel)
            await assembleTomorrowFromLifeModel(userId: userId)
        } else {
            await seedInitialTasksFromProfile(userId: userId, sections: nil)
            await tasksVM.ensureDailyRoutineTasks(userId: userId)
        }

        UserLifeProfileStore.syncUserNameFromProfileIfNeeded()

        let completed = tasksVM.completedToday
        let pending = tasksVM.tasks.filter { $0.status.isActive }
        let focusMins = resolvedFocusMinutes(userId: userId, completed: completed)
        brain.updateLiveProgress(
            completedTasks: completed,
            pendingTasks: pending,
            focusMinutes: focusMins,
            health: brainVM.healthSummary,
            executiveCapacityLabel: contextOrchestrator.executiveCapacity.band.displayLabel,
            actualFocusMinutes: focusMins
        )
        rebuildTimelineFromTasks(immediate: true)
        syncWidgetDataOnly()
        LiveActivityManager.shared.endOrphanedFocusActivitiesOnLaunch(
            manualFocusActive: adhdVM.isFocusSessionActive,
            executionProjects: false
        )
        if WidgetSyncService.shared.isNowPinned {
            LiveActivityManager.shared.reattachNowPinIfNeeded()
        }
        startExecutionEnvironment()

        await seedUITestFocusTaskIfNeeded(userId: userId)

        let userName = UserLifeProfileStore.resolvedDisplayName()
        await refreshContext(
            userId: userId,
            userName: userName,
            peakStartHour: UserLifeProfileStore.load().peakStartHour
        )
        startContextLoop(userId: userId)

        if UITestLaunchConfiguration.shouldAutoStartFocusSession {
            startFocusSessionForUITestIfNeeded(userId: userId)
        }

        scheduleAppleCalendarSync()
    }

    func configureCaptureRouter(userId: String) {
        let router = CaptureRouter.shared
        router.onCreateTask = { [weak self] draft, inboxItemId in
            guard let self else { throw CaptureRouterError.unavailable }
            return try await self.tasksVM.createFromInbox(draft, userId: userId, sourceInboxItemId: inboxItemId)
        }
        router.onCreateScheduledTask = { [weak self] draft, scheduledAt, inboxItemId in
            guard let self else { throw CaptureRouterError.unavailable }
            return try await self.tasksVM.createScheduledFromCapture(
                draft,
                scheduledAt: scheduledAt,
                userId: userId,
                sourceInboxItemId: inboxItemId
            )
        }
        router.onJournalEntry = { [weak self] content, mood in
            guard let self else { throw CaptureRouterError.unavailable }
            await self.modulesVM.addJournalEntry(content: content, mood: mood, gratitudes: [])
            return self.modulesVM.journalEntries.first?.id ?? UUID().uuidString
        }
        router.onHealthLog = { [weak self] mood, note, uid in
            guard let self else { throw CaptureRouterError.unavailable }
            let energy: EnergyLevel = mood == "Low" ? .low : (mood == "Good" || mood == "Great" ? .high : .moderate)
            await self.brainVM.logEnergyReport(energy: energy, focusNote: note, userId: uid)
        }
        router.onInboxItemsChanged = { [weak self] in
            guard let self else { return }
            await self.inboxVM.loadItems(userId: userId)
            self.refreshWidgetData()
        }
        CaptureOfflineQueue.shared.onConnectivityRestored = { [weak self] uid in
            guard let self else { return }
            await self.inboxVM.processOfflineCaptureQueue(userId: uid)
            self.refreshWidgetData()
        }
        Task {
            await inboxVM.processOfflineCaptureQueue(userId: userId)
        }
    }

    /// Debounced mirror of today's scheduled tasks into Apple Calendar.
    func scheduleAppleCalendarSync() {
        guard CalendarSyncSettings.syncTasksToAppleCalendar else { return }
        calendarSyncDebounceTask?.cancel()
        calendarSyncDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.syncTodayTasksToAppleCalendar()
        }
    }

    func syncTodayTasksToAppleCalendar() async {
        guard CalendarSyncSettings.syncTasksToAppleCalendar else { return }
        let pool = tasksVM.tasks + tasksVM.completedToday
        do {
            let changed = try await calendarSyncService.syncScheduledTasks(pool, on: Date())
            if !changed.isEmpty {
                await tasksVM.applyCalendarEventIdentifiers(changed)
            }
        } catch CalendarSyncError.accessDenied {
            // Stay silent when the user declines calendar access.
        } catch {
            print("[CalendarSync] \(error.localizedDescription)")
        }
    }

    private func seedUITestFocusTaskIfNeeded(userId: String) async {
        guard UITestLaunchConfiguration.shouldSeedFocusTask else { return }
        let taskId = UITestLaunchConfiguration.focusTaskId
        guard !tasksVM.tasks.contains(where: { $0.id == taskId }) else { return }

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .hour, value: 1, to: day) ?? day
        let end = calendar.date(byAdding: .minute, value: 45, to: start) ?? start

        let task = LifeTask(
            id: taskId,
            title: "UITest focus task",
            lifeArea: .work,
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: start,
            schedulingMode: .flexible,
            scheduledEndTime: end,
            userId: userId
        )

        tasksVM.createTask(task)
    }

    /// Creates fixed + flexible starter tasks from the life profile once after onboarding.
    func seedInitialTasksFromProfile(
        userId: String,
        sections: StructuredLifeProfileSections?
    ) async {
        let resolvedUserId = resolvedUserId(userId)
        guard !resolvedUserId.isEmpty else {
            print("[Onboarding] seed skipped — no userId")
            return
        }

        var profile = UserLifeProfileStore.load()
        guard profile.hasCompletedOnboarding else {
            print("[Onboarding] seed skipped — onboarding not completed")
            return
        }

        if LifeModelStore.hasCompiledModel {
            print("[Onboarding] seed skipped — life model drives commitments")
            return
        }

        ProfileScheduleSync.enrichFixedScheduleNotes(profile: &profile, sections: sections)
        UserLifeProfileStore.save(profile)

        if profile.hasSeededInitialTasks, tasksVM.hasOnboardingTaggedTasks(userId: resolvedUserId) {
            if await tasksVM.onboardingTasksNeedCleanup(userId: resolvedUserId) {
                print("[Onboarding] cleaning junk seeded tasks and re-seeding")
                await tasksVM.removeOnboardingSeededTasks(userId: resolvedUserId)
                profile.hasSeededInitialTasks = false
            } else {
                print("[Onboarding] seed skipped — already seeded")
                return
            }
        }

        if profile.hasSeededInitialTasks, !tasksVM.hasOnboardingTaggedTasks(userId: resolvedUserId) {
            print("[Onboarding] re-seeding — flag set but no onboarding tasks found")
            profile.hasSeededInitialTasks = false
        }

        let seed = OnboardingTaskSeeder.seedTasks(from: profile, sections: sections)
        print("[Onboarding] seeding \(seed.allTasks.count) tasks (\(seed.fixedTasks.count) fixed, \(seed.flexibleTasks.count) flexible)")

        await tasksVM.importOnboardingTasks(seed.allTasks, userId: resolvedUserId)

        profile.hasSeededInitialTasks = true
        UserLifeProfileStore.save(profile)
        refreshWidgetData()
    }

    /// Compiles markdown into a structured LifeModel and persists it.
    @discardableResult
    func compileAndSaveLifeModel(markdown: String) async -> LifeModel {
        let compiler = LifeModelCompiler()
        let model = await compiler.compile(markdown: markdown)
        LifeModelStore.save(model)
        LifeModelStore.syncProfileFields(from: model)
        return model
    }

    /// Assembles today's commitment tasks from the compiled life model.
    func assembleDayFromLifeModel(userId: String) async {
        guard let model = LifeModelStore.load(), model.hasContent else { return }
        await tasksVM.ensureLifeCommitmentTasks(userId: userId, model: model)
        refreshWidgetData()
    }

    /// Assembles tomorrow's commitment tasks so the preview timeline is populated.
    func assembleTomorrowFromLifeModel(userId: String) async {
        guard let model = LifeModelStore.load(), model.hasContent else { return }
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) else { return }
        await tasksVM.ensureLifeCommitmentTasks(userId: userId, model: model, date: tomorrow, calendar: calendar)
        refreshWidgetData()
    }

    private func compileLifeModelIfNeeded() async {
        guard !LifeModelStore.hasCompiledModel else { return }

        let profileText = UserLifeProfileStore.load().profileText
        guard profileText.contains("# My ") || profileText.contains("# My Core Identity") else { return }
        _ = await compileAndSaveLifeModel(markdown: profileText)
    }

    /// Materializes starter tasks from profile + compiled life model for onboarding review.
    func materializeStarterTasks(
        userId: String,
        sections: StructuredLifeProfileSections? = nil
    ) async {
        let resolvedUserId = resolvedUserId(userId)
        guard !resolvedUserId.isEmpty else { return }

        var profile = UserLifeProfileStore.load()
        ProfileScheduleSync.enrichFixedScheduleNotes(profile: &profile, sections: sections)
        UserLifeProfileStore.save(profile)

        let profileText = profile.profileText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !profileText.isEmpty, !LifeModelStore.hasCompiledModel {
            _ = await compileAndSaveLifeModel(markdown: profileText)
        }

        await tasksVM.removeOnboardingSeededTasks(userId: resolvedUserId)
        profile.hasSeededInitialTasks = false
        UserLifeProfileStore.save(profile)

        if let model = LifeModelStore.load(), model.hasContent {
            await tasksVM.ensureLifeCommitmentTasks(userId: resolvedUserId, model: model)
        } else {
            await seedInitialTasksFromProfile(userId: resolvedUserId, sections: sections)
        }

        profile = UserLifeProfileStore.load()
        profile.hasSeededInitialTasks = true
        UserLifeProfileStore.save(profile)

        await refreshContext(
            userId: resolvedUserId,
            userName: UserLifeProfileStore.resolvedDisplayName(),
            peakStartHour: UserLifeProfileStore.load().peakStartHour
        )
        refreshWidgetData()
    }

    /// Re-reads the life profile and recreates onboarding starter tasks (e.g. after Organize with AI).
    func refreshTasksFromProfile(
        userId: String,
        sections: StructuredLifeProfileSections? = nil
    ) async {
        let resolvedUserId = resolvedUserId(userId)
        guard !resolvedUserId.isEmpty else { return }

        var profile = UserLifeProfileStore.load()
        ProfileScheduleSync.enrichFixedScheduleNotes(profile: &profile, sections: sections)
        UserLifeProfileStore.save(profile)

        await tasksVM.removeOnboardingSeededTasks(userId: resolvedUserId)
        profile.hasSeededInitialTasks = false
        UserLifeProfileStore.save(profile)

        await seedInitialTasksFromProfile(userId: resolvedUserId, sections: sections)

        await refreshContext(
            userId: resolvedUserId,
            userName: UserLifeProfileStore.resolvedDisplayName(),
            peakStartHour: UserLifeProfileStore.load().peakStartHour
        )
        refreshWidgetData()
    }

    private func resolvedUserId(_ userId: String) -> String {
        accountIdentity.resolved(userId)
    }

    private var contextLoopTask: Task<Void, Never>?
    /// Prevents overlapping context refreshes from the background loop.
    private var isContextRefreshInFlight = false
    private struct PendingContextRefresh {
        var userId: String
        var userName: String
        var peakStartHour: Int
        var capacityLLMPolicy: ExecutiveCapacityLLMPolicy
    }
    private var pendingContextRefresh: PendingContextRefresh?
    private var didForceInitialTaskSync = false

    // Bootstrap task / completion state lives on BootstrapCoordinator (Phase 4.1).

    private var timelineRebuildTask: Task<Void, Never>?
    private var syncWidgetsAfterDebouncedRebuild = false
    private static let timelineRebuildDebounceNs: UInt64 = 75_000_000

    /// Keeps brain/timeline fresh while the app is open. Capacity stays deterministic — no LLM polling.
    /// Performance: skips ticks while a refresh is already running or a focus session is active.
    /// Interval is 90s (was 60s) and alternate ticks use briefing-only refresh (PERF-003).
    func startContextLoop(userId: String) {
        contextLoopTask?.cancel()
        contextLoopTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 90_000_000_000)
                guard let self, !Task.isCancelled, !self.isPerformingFactoryReset else { return }
                // Skip while focus UI is up — avoids jank on the timer screen.
                guard !self.adhdVM.isFocusSessionActive else { continue }
                // Skip if a previous refresh is still running.
                guard !self.isContextRefreshInFlight else { continue }

                tick &+= 1
                let userName = UserLifeProfileStore.resolvedDisplayName()
                let peak = UserLifeProfileStore.load().peakStartHour
                // Full reconcile every other tick; light surface refresh in between.
                if tick.isMultiple(of: 2) {
                    await self.refreshContext(
                        userId: userId,
                        userName: userName,
                        peakStartHour: peak,
                        capacityLLMPolicy: .deterministicOnly
                    )
                } else {
                    await self.refreshBriefingSurface(
                        userId: userId,
                        userName: userName,
                        peakStartHour: peak,
                        capacityLLMPolicy: .deterministicOnly,
                        refreshHealth: false
                    )
                }
            }
        }
    }

    func requestDebouncedTimelineRebuild(reason: String = "") {
        rebuildTimelineFromTasks(immediate: false)
    }

    func refreshWidgetData(rebuildTimeline: Bool = true, immediateTimelineRebuild: Bool = false) {
        if rebuildTimeline {
            if immediateTimelineRebuild {
                rebuildTimelineFromTasks(immediate: true)
                syncWidgetDataOnly()
                syncExecutionEnvironment()
            } else {
                syncWidgetsAfterDebouncedRebuild = true
                rebuildTimelineFromTasks(immediate: false)
            }
        } else {
            syncWidgetDataOnly()
            syncExecutionEnvironment()
        }
    }

    private func syncWidgetDataOnly() {
        WidgetSyncService.shared.sync(
            brainVM: brainVM,
            taskStore: taskStore,
            healthStore: healthStore,
            scheduleTasks: tasksVM.tasks + tasksVM.completedToday,
            timelineEvents: timelineService.snapshot.today
        )
    }

    func refreshPinNow() {
        guard WidgetSyncService.shared.isNowPinned else { return }
        rebuildTimelineFromTasks(immediate: true)
        Task {
            await WidgetSyncService.shared.refreshPinNow(
                brainVM: brainVM,
                taskStore: taskStore,
                healthStore: healthStore,
                scheduleTasks: tasksVM.tasks + tasksVM.completedToday,
                timelineEvents: timelineService.snapshot.today
            )
        }
    }

    /// Starts schedule-driven Focus Filters + Live Activities.
    func startExecutionEnvironment() {
        let coordinator = ExecutionEnvironmentCoordinator.shared
        coordinator.onPinRefreshNeeded = { [weak self] in
            self?.refreshPinNow()
        }
        coordinator.setManualFocusActive(adhdVM.isFocusSessionActive)
        coordinator.updateTasks(tasksVM.tasks + tasksVM.completedToday)
        coordinator.start()
    }

    func syncExecutionEnvironment() {
        let coordinator = ExecutionEnvironmentCoordinator.shared
        coordinator.setManualFocusActive(adhdVM.isFocusSessionActive)
        coordinator.updateTasks(tasksVM.tasks + tasksVM.completedToday)
        coordinator.refresh()
    }

    func prepareExecutionEnvironmentForBackground() {
        let coordinator = ExecutionEnvironmentCoordinator.shared
        coordinator.setManualFocusActive(adhdVM.isFocusSessionActive)
        coordinator.updateTasks(tasksVM.tasks + tasksVM.completedToday)
        coordinator.prepareForBackground()
    }

    func stopExecutionEnvironment() {
        ExecutionEnvironmentCoordinator.shared.stop()
    }

    func orchestrateBrain(userId: String) async {
        let signpost = PerformanceSignposts.beginOrchestrateBrain()
        defer { PerformanceSignposts.endOrchestrateBrain(signpost) }
        let uid = resolvedUserId(userId)
        guard !uid.isEmpty else { return }
        await ensureFlowDirector()
        await brainVM.refresh(userId: uid, activeFlowSession: activeFlowSessionState())
        if brainVM.isUsingFlowDirector, let surface = brainVM.flowSurface {
            FlowDirectorIntegrationLog.recordOrchestration(
                surface: surface,
                durationMs: brainVM.lastOrchestrationDurationMs
            )
        }
    }

    func refreshContext(
        userId: String,
        userName: String = "",
        peakStartHour: Int = 9,
        capacityLLMPolicy: ExecutiveCapacityLLMPolicy = .deterministicOnly
    ) async {
        guard !isPerformingFactoryReset else { return }
        if isContextRefreshInFlight {
            pendingContextRefresh = PendingContextRefresh(
                userId: userId,
                userName: userName,
                peakStartHour: peakStartHour,
                capacityLLMPolicy: capacityLLMPolicy
            )
            return
        }
        isContextRefreshInFlight = true
        let contextSignpost = PerformanceSignposts.beginContextRefresh()
        defer {
            PerformanceSignposts.endContextRefresh(contextSignpost)
            isContextRefreshInFlight = false
            if let pending = pendingContextRefresh {
                pendingContextRefresh = nil
                Task { await self.refreshContext(
                    userId: pending.userId,
                    userName: pending.userName,
                    peakStartHour: pending.peakStartHour,
                    capacityLLMPolicy: pending.capacityLLMPolicy
                ) }
            }
        }

        accountIdentity.refresh()
        let uid = resolvedUserId(userId)
        guard !uid.isEmpty else { return }
        let resolvedName = userName.isEmpty ? ProfileCoordinator.displayName : userName
        let peakHour = peakStartHour > 0 ? peakStartHour : ProfileCoordinator.peakStartHour
        await tasksVM.compactTaskStorageIfNeeded(userId: uid)
        let forceTaskSync = !didForceInitialTaskSync
        didForceInitialTaskSync = true
        await tasksVM.syncScheduleAndReconcileToday(
            userId: uid,
            forceRecurrenceSync: true,
            localRecurrenceOnly: !forceTaskSync
        )
        await healthStore.refresh(userId: uid)
        await orchestrateBrain(userId: uid)
        rebuildTimelineFromTasks(immediate: true)
        await projectBriefingSurface(
            userId: uid,
            resolvedName: resolvedName,
            peakHour: peakHour,
            capacityLLMPolicy: capacityLLMPolicy
        )
    }

    /// Read-mostly briefing refresh — updates hero, health, and brain presentation without schedule reconcile.
    func refreshBriefingSurface(
        userId: String,
        userName: String = "",
        peakStartHour: Int = 9,
        capacityLLMPolicy: ExecutiveCapacityLLMPolicy = .deterministicOnly,
        refreshHealth: Bool = true
    ) async {
        guard !isPerformingFactoryReset else { return }
        accountIdentity.refresh()
        let uid = resolvedUserId(userId)
        guard !uid.isEmpty else { return }
        let resolvedName = userName.isEmpty ? ProfileCoordinator.displayName : userName
        let peakHour = peakStartHour > 0 ? peakStartHour : ProfileCoordinator.peakStartHour
        if refreshHealth {
            await healthStore.refresh(userId: uid)
        }
        await orchestrateBrain(userId: uid)
        await projectBriefingSurface(
            userId: uid,
            resolvedName: resolvedName,
            peakHour: peakHour,
            capacityLLMPolicy: capacityLLMPolicy
        )
    }

    /// Syncs in-memory task state, reconciles overlaps, and rebuilds timeline after AI reschedule apply.
    func syncScheduleAfterRescheduleApply(userId: String) async {
        let uid = resolvedUserId(userId)
        guard !uid.isEmpty else { return }
        tasksVM.syncFromTaskStore()
        await tasksVM.reconcileTodaySchedule(userId: uid)
        rebuildTimelineFromTasks(immediate: true)
        refreshWidgetData(rebuildTimeline: false)
    }

    private func projectBriefingSurface(
        userId uid: String,
        resolvedName: String,
        peakHour: Int,
        capacityLLMPolicy: ExecutiveCapacityLLMPolicy
    ) async {
        let shoppingCount = modulesVM.shoppingItems.filter { !$0.isPurchased }.count
        let bills = modulesVM.bills.filter { !$0.isPaid }
        let medications = MedicationStore.load()
        let lifeEvents = timelineService.snapshot.today
        let tomorrowEvents = timelineService.snapshot.tomorrow
        let timeline = lifeEvents
        let isWeekend = Calendar.current.isDateInWeekend(Date())
        await contextOrchestrator.refresh(
            .init(
                userId: uid,
                userName: resolvedName,
                cognitiveSnapshot: brainVM.cognitiveSnapshot,
                healthSummary: brainVM.healthSummary,
                flowSurface: brainVM.flowSurface,
                activeFlowSession: activeFlowSessionState(),
                heroTask: brainVM.flowSurface?.heroTask
                    ?? brainVM.topTasks.first
                    ?? tasksVM.tasks.first(where: { $0.status.isActive }),
                topTasks: {
                    let brainTasks = brainVM.topTasks.filter(\.status.isActive)
                    if !brainTasks.isEmpty { return brainTasks }
                    return Array(tasksVM.tasks.filter(\.status.isActive).prefix(8))
                }(),
                unpurchasedShoppingCount: shoppingCount,
                upcomingBills: bills,
                lifeTimelineEvents: lifeEvents,
                tomorrowLifeTimelineEvents: tomorrowEvents,
                isWeekend: isWeekend,
                peakStartHour: peakHour,
                allTasks: tasksVM.tasks,
                completedTaskIDs: Set(tasksVM.completedToday.map(\.id)),
                flowConfidenceScore: brainVM.flowSurface?.confidence,
                capacityLLMPolicy: capacityLLMPolicy
            )
        )
        let projected = BriefingProjector.project(
            BriefingProjectorInput(
                userName: resolvedName,
                heroBriefing: contextOrchestrator.briefing?.hero,
                brainDecision: contextOrchestrator.brainState?.decision,
                flowSurface: brainVM.flowSurface,
                recommendation: brainVM.recommendation,
                topTasks: brainVM.topTasks,
                resumeSnapshot: contextOrchestrator.resumeSnapshot,
                executiveCapacity: contextOrchestrator.executiveCapacity,
                lifeSnapshot: contextOrchestrator.snapshot,
                cognitiveSnapshot: brainVM.cognitiveSnapshot,
                healthSummary: brainVM.healthSummary,
                activeTasks: tasksVM.tasks.filter(\.status.isActive),
                upcomingBills: bills,
                medications: medications,
                timelineItems: timeline
            )
        )
        briefingVM.applyProjectedSurface(projected)
        briefingVM.updateExecutiveCapacity(contextOrchestrator.executiveCapacity)
        await briefingVM.refresh(
            brainVM: brainVM,
            tasksVM: tasksVM,
            userId: uid,
            userName: resolvedName,
            healthKitAvailable: healthKitEnabled,
            heroBriefing: contextOrchestrator.briefing?.hero,
            brainDecision: contextOrchestrator.brainState?.decision,
            lifeSnapshot: contextOrchestrator.snapshot,
            lifeTimelineEvents: timelineService.snapshot.today,
            tomorrowLifeTimelineEvents: timelineService.snapshot.tomorrow
        )
        await refreshProactiveActions(userId: uid)
        refreshWidgetData(rebuildTimeline: false)
        evaluateManualSleepPrompt()

        brainVM.applyPresentation(
            BriefingProjector.project(
                BriefingProjectorInput(
                    userName: resolvedName,
                    heroBriefing: contextOrchestrator.briefing?.hero,
                    brainDecision: contextOrchestrator.brainState?.decision,
                    flowSurface: brainVM.flowSurface,
                    recommendation: brainVM.recommendation,
                    topTasks: brainVM.topTasks,
                    resumeSnapshot: contextOrchestrator.resumeSnapshot,
                    executiveCapacity: contextOrchestrator.executiveCapacity,
                    lifeSnapshot: contextOrchestrator.snapshot,
                    cognitiveSnapshot: brainVM.cognitiveSnapshot,
                    healthSummary: brainVM.healthSummary,
                    activeTasks: tasksVM.tasks.filter(\.status.isActive),
                    upcomingBills: bills,
                    medications: medications,
                    timelineItems: timeline,
                    readinessLabel: briefingVM.healthSnapshot.readinessLabel
                )
            ).brainPresentation
        )

        let completed = tasksVM.completedToday
        let pending = tasksVM.tasks.filter { $0.status.isActive }
        let focusMins = resolvedFocusMinutes(userId: uid, completed: completed)
        brain.updateLiveProgress(
            completedTasks: completed,
            pendingTasks: pending,
            focusMinutes: focusMins,
            health: brainVM.healthSummary,
            executiveCapacityLabel: contextOrchestrator.executiveCapacity.band.displayLabel,
            actualFocusMinutes: focusMins
        )
        await NotificationCoordinator.shared.refreshFromShell(self)
    }

    /// Keeps Executive Brain coach context in sync after task completions — without a full context refresh.
    func syncBrainLiveProgress(userId: String) {
        let completed = tasksVM.completedToday
        let pending = tasksVM.tasks.filter { $0.status.isActive }
        let focusMins = resolvedFocusMinutes(userId: userId, completed: completed)
        brain.updateLiveProgress(
            completedTasks: completed,
            pendingTasks: pending,
            focusMinutes: focusMins,
            health: brainVM.healthSummary,
            executiveCapacityLabel: contextOrchestrator.executiveCapacity.band.displayLabel,
            actualFocusMinutes: focusMins
        )
    }

    /// Rebuilds timeline snapshot from in-memory task state (no network / recurrence sync).
    func rebuildTimelineFromTasks(immediate: Bool = false) {
        if immediate {
            timelineRebuildTask?.cancel()
            timelineRebuildTask = nil
            performTimelineRebuild()
            return
        }
        timelineRebuildTask?.cancel()
        timelineRebuildTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.timelineRebuildDebounceNs)
            guard !Task.isCancelled, let self else { return }
            self.performTimelineRebuild()
            if self.syncWidgetsAfterDebouncedRebuild {
                self.syncWidgetsAfterDebouncedRebuild = false
                self.syncWidgetDataOnly()
                self.syncExecutionEnvironment()
            }
            self.timelineRebuildTask = nil
        }
    }

    private func performTimelineRebuild() {
        timelineService.rebuild(
            tasks: tasksVM.tasks,
            completedToday: tasksVM.completedToday,
            recurrenceTemplates: tasksVM.recurrenceTemplates,
            bills: modulesVM.bills,
            shoppingItems: modulesVM.shoppingItems,
            contacts: modulesVM.contacts,
            medications: MedicationStore.load()
        )
        if let change = CalendarChangeDetector.evaluate(timelineEvents: timelineService.snapshot.today) {
            pendingCalendarChange = change
        }
    }

    func refreshProactiveActions(userId: String) async {
        let uid = resolvedUserId(userId)
        guard !uid.isEmpty else { return }

        let heroTask = brainVM.flowSurface?.heroTask
            ?? brainVM.topTasks.first
            ?? tasksVM.tasks.first(where: { $0.status.isActive })
        let behavior = await ProactiveActionsBuilder.loadBehaviorMemory()
        let captureEdges = await ProactiveActionsBuilder.loadCaptureGraphEdges()
        let analytics = BackgroundAnalyticsService.shared.cachedAIContext(userId: uid)
        let elapsedMinutes = adhdVM.isFocusSessionActive
            ? max(0, Int(adhdVM.focusSessionElapsed / 60))
            : 0

        let snapshot = ProactiveActionsBuilder.ShellSnapshot(
            tasks: tasksVM.schedulingContext,
            timelineEvents: timelineService.snapshot.today,
            inboxItems: inboxVM.items,
            memoryEntries: modulesVM.memoryEntries,
            contacts: modulesVM.contacts,
            heroTask: heroTask,
            focusSessionActive: adhdVM.isFocusSessionActive,
            focusSessionElapsedMinutes: elapsedMinutes,
            focusTaskTitle: adhdVM.currentFocusTask?.title,
            capacityBand: contextOrchestrator.executiveCapacity.band,
            energyPercent: briefingVM.energy.currentEnergyPercent,
            completedTodayCount: briefingVM.progress.completedCount,
            analyticsContext: analytics,
            behaviorMemory: behavior,
            calendarChange: pendingCalendarChange,
            bills: modulesVM.bills,
            shoppingItems: modulesVM.shoppingItems,
            medications: MedicationStore.load(),
            sleepHours: brainVM.healthSummary?.totalSleepMinutes.map { $0 / 60.0 },
            captureGraphEdges: captureEdges
        )
        proactiveActions = ProactiveActionsBuilder.analyze(snapshot: snapshot)
        let integrationActions = await IntegrationProactiveBridge.emailAndTravelActions(
            timelineEvents: timelineService.snapshot.today
        )
        proactiveActions = integrationActions + proactiveActions
        storeAutoApplyPreviewTimeouts()
        await emitExpiredPreviewConfirmationIfNeeded()
        ProactiveSnapshotStore.save(proactiveActions)
        briefingVM.setProactiveActions(proactiveActions)
        for action in proactiveActions where action.kind == .initiationBridge {
            AccountabilityScheduler.scheduleIfEnabled(for: action)
        }
    }

    private func storeAutoApplyPreviewTimeouts() {
        for action in proactiveActions where action.surface == .autoApplyPreview {
            if let bundle = ProactiveActionBundleCodec.decode(from: action) {
                ProactivePreviewTimeoutStore.save(
                    action: action,
                    bundle: bundle,
                    expiresAt: Date().addingTimeInterval(15 * 60)
                )
            }
        }
    }

    private func emitExpiredPreviewConfirmationIfNeeded() async {
        guard let pending = ProactivePreviewTimeoutStore.load(), pending.expiresAt <= Date() else { return }
        ProactivePreviewTimeoutStore.clear()
        guard NotificationPermissionService.shared.isAuthorized else { return }
        let candidate = NotificationCandidate(
            id: NotificationIdentifier.proactive(.brainHero, suffix: "previewConfirm.\(pending.actionID)"),
            kind: .brainHero,
            title: "Replan ready",
            body: "Your calendar change preview expired — tap to confirm before applying.",
            fireDate: Date().addingTimeInterval(30),
            route: .today,
            proactiveKind: pending.kind
        )
        await NotificationScheduler.shared.scheduleSnooze(for: candidate, fireDate: candidate.fireDate)
    }

    func clearPendingCalendarChange() {
        pendingCalendarChange = nil
    }

    private func resetBootstrapAndTimelineCoordinators() {
        bootstrapCoordinator.reset()
        session?.tearDown()
        session = nil
        identityService.refreshFromFirebase()
        timelineRebuildTask?.cancel()
        timelineRebuildTask = nil
        syncWidgetsAfterDebouncedRebuild = false
    }

    private var healthKitEnabled: Bool {
        (UserDefaults.standard.object(forKey: "enableHealth") as? Bool ?? true) && HealthManager().isAvailable
    }

    /// Erases every persisted layer and reboots the app like a fresh install (account and license preserved).
    func performFactoryReset(userId: String, healthSync: HealthSyncService) async {
        isPerformingFactoryReset = true
        contextLoopTask?.cancel()
        contextLoopTask = nil
        BackgroundAnalyticsScheduler.shared.stop()
        BackgroundAnalyticsService.shared.resetForFactoryReset()

        FactoryResetManager.shared.performLocalReset(userId: userId)
        clearInMemoryState(userId: userId)
        healthSync.resetForFactoryReset()
        stopExecutionEnvironment()
        LiveActivityManager.shared.endAllActivities()
        await NotificationCoordinator.shared.resetForFactoryReset()
        refreshWidgetData(immediateTimelineRebuild: true)
        factoryResetGeneration += 1

        await FactoryResetManager.shared.resetCloudIfAvailable()
        await bootstrapFreshStart(userId: userId, healthSync: healthSync)
        FactoryResetManager.shared.finishFreshInstall()
        isPerformingFactoryReset = false
    }

    /// First-install bootstrap after factory reset — full HealthKit import and brain rebuild.
    func bootstrapFreshStart(userId: String, healthSync: HealthSyncService) async {
        guard !userId.isEmpty else { return }
        isBootstrappingFreshStart = true
        defer {
            isBootstrappingFreshStart = false
            FactoryResetManager.shared.clearPendingFreshStart()
        }

        BackgroundAnalyticsScheduler.shared.start(userId: userId)
        brain.personalizationContext = nil

        await healthSync.syncHealthData(userId: userId)

        await ensureFlowDirector()
        async let brainLoad: Void = orchestrateBrain(userId: userId)
        async let taskLoad: Void = tasksVM.refreshFromLocal(userId: userId)
        async let moduleLoad: Void = modulesVM.loadAllData(userId: userId)
        async let inboxLoad: Void = inboxVM.loadItems(userId: userId)
        _ = await (brainLoad, taskLoad, moduleLoad, inboxLoad)

        let completed = tasksVM.completedToday
        let pending = tasksVM.tasks.filter { $0.status.isActive }
        let focusMins = resolvedFocusMinutes(userId: userId, completed: completed)
        brain.updateLiveProgress(
            completedTasks: completed,
            pendingTasks: pending,
            focusMinutes: focusMins,
            health: brainVM.healthSummary,
            executiveCapacityLabel: contextOrchestrator.executiveCapacity.band.displayLabel,
            actualFocusMinutes: focusMins
        )
        refreshWidgetData(immediateTimelineRebuild: true)
        startExecutionEnvironment()

        UserLifeProfileStore.syncUserNameFromProfileIfNeeded()

        let userName = UserLifeProfileStore.resolvedDisplayName()
        await refreshContext(
            userId: userId,
            userName: userName,
            peakStartHour: UserLifeProfileStore.load().peakStartHour
        )
        startContextLoop(userId: userId)
    }

    private func clearInMemoryState(userId: String) {
        resetBootstrapAndTimelineCoordinators()
        brainVM.resetForFactoryReset()
        contextOrchestrator.resetInMemoryState()
        tasksVM.tasks = []
        tasksVM.completedToday = []
        modulesVM.resetInMemoryState()
        inboxVM.resetInMemoryState()
        briefingVM.resetAfterDeveloperWipe()
        adhdVM.endFocusSession()
        continueSession.endSession()
        timelineService.factoryReset()
        flowDirector = nil
        flowDirectorUserName = ""
        ResumeEngine.shared.clear(userId: userId)
        PostWakeSessionStore.resetForFactoryReset()
        UserDayConstraintStore.resetForFactoryReset()
        ManualSleepLogStore.resetForFactoryReset()
        CalendarChangeDetector.resetFingerprint()
        AppForegroundTracker.reset()
        proactiveActions = []
        pendingCalendarChange = nil
    }

    func evaluateManualSleepPrompt() {
        guard !isPerformingFactoryReset else { return }
        showManualSleepSheet = ManualSleepLogStore.shouldPrompt(
            healthSummary: brainVM.rawHealthSummary ?? brainVM.healthSummary
        )
    }

    func submitManualSleep(_ rating: ManualSleepRating, userId: String) async {
        ManualSleepLogStore.save(rating: rating)
        showManualSleepSheet = false
        let name = UserLifeProfileStore.resolvedDisplayName()
        let peak = UserLifeProfileStore.load().peakStartHour
        await refreshContext(
            userId: userId,
            userName: name,
            peakStartHour: peak,
            capacityLLMPolicy: .deterministicOnly
        )
    }

    func dismissManualSleepPromptForToday() {
        ManualSleepLogStore.dismissForToday()
        showManualSleepSheet = false
    }

    func persistResume(
        userId: String,
        screen: String,
        experienceMode: ExperienceMode?,
        aiPreview: String? = nil
    ) {
        let activeTask = adhdVM.currentFocusTask ?? brainVM.flowSurface?.heroTask
        contextOrchestrator.persistResume(
            userId: userId,
            screen: screen,
            experienceMode: experienceMode,
            activeTask: activeTask,
            focusSession: activeFlowSessionState(),
            aiPreview: aiPreview ?? latestAIPreview()
        )
    }

    func activeFlowSessionState() -> FlowSessionState? {
        guard adhdVM.isFocusSessionActive, let task = adhdVM.currentFocusTask else { return nil }
        return FlowSessionState(
            isActive: true,
            taskID: task.id,
            elapsedSeconds: Int(adhdVM.focusSessionElapsed),
            targetSeconds: Int(adhdVM.focusSessionTarget),
            isPaused: adhdVM.isPaused,
            isResting: adhdVM.isOnBreak
        )
    }

    public func ensureFlowDirector() async {
        guard FlowDirectorFeature.isEnabled else { return }
        let name = UserLifeProfileStore.resolvedDisplayName()
        if flowDirector == nil || flowDirectorUserName != name {
            flowDirector = await FlowDirectorFactory.make(userName: name)
            if let director = flowDirector {
                brainVM.configure(flowDirector: director)
                // Phase 3: FlowDirector as primary BrainFacade backend when flag on.
                brainVM.configure(brainFacade: FlowAwareBrainFacade(director: director))
                flowDirectorUserName = name
                FlowDirectorIntegrationLog.log("FlowDirector wired from AppShellState")
            }
        }
    }

    private func latestAIPreview() -> String? {
        brain.chatHistory.last?.content
    }

    private func resolvedFocusMinutes(userId: String, completed: [LifeTask]) -> Int {
        if let deepWorkHours = BackgroundAnalyticsService.shared.cachedAIContext(userId: userId)?.deepWorkHours,
           deepWorkHours > 0 {
            return Int(deepWorkHours * 60)
        }
        let actual = completed.compactMap(\.actualMinutes).reduce(0, +)
        if actual > 0 { return actual }
        return completed.reduce(0) { $0 + $1.estimatedMinutes }
    }

    /// UITest hook — starts a focus session immediately after bootstrap for perf measurement.
    func startFocusSessionForUITestIfNeeded(userId: String) {
        guard UITestLaunchConfiguration.shouldAutoStartFocusSession else { return }
        guard !adhdVM.isFocusSessionActive else { return }

        let task = tasksVM.tasks.first(where: { $0.status.isActive })
            ?? LifeTask(
                title: "UITest focus block",
                lifeArea: .work,
                estimatedMinutes: 25,
                userId: userId
            )
        adhdVM.startFocusSession(task: task)
    }
}

// MARK: - BootstrapExecuting

extension AppShellState: BootstrapExecuting {}
