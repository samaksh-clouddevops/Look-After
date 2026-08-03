import Foundation
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
    let tasksVM: TasksViewModel
    let modulesVM: LifeModulesViewModel
    let adhdVM: ADHDViewModel
    let briefingVM: DailyBriefingViewModel
    let inboxVM: InboxViewModel
    let contextOrchestrator: ContextOrchestrator
    let continueSession: ContinueSessionController

    /// Incremented after factory reset so child views can wipe local @StateObject state.
    @Published private(set) var factoryResetGeneration = 0
    @Published private(set) var isPerformingFactoryReset = false
    @Published private(set) var isBootstrappingFreshStart = false

    private var flowDirector: FlowDirector?
    private var flowDirectorUserName: String = ""

    init() {
        let glm = GLMService.shared
        let executiveBrain = ExecutiveBrain(glmService: glm)
        brain = executiveBrain
        brainVM = BrainViewModel(brain: executiveBrain)
        tasksVM = TasksViewModel(decomposer: TaskDecomposer(glmService: glm))
        modulesVM = LifeModulesViewModel()
        adhdVM = ADHDViewModel()
        briefingVM = DailyBriefingViewModel()
        inboxVM = InboxViewModel(glmService: glm)
        contextOrchestrator = ContextOrchestrator(glmService: glm)
        continueSession = ContinueSessionController()
    }

    func bootstrap(userId: String, healthSync: HealthSyncService) {
        guard !userId.isEmpty else { return }

        if FactoryResetManager.shared.isPendingFreshStart {
            Task { await bootstrapFreshStart(userId: userId, healthSync: healthSync) }
            return
        }

        BackgroundAnalyticsScheduler.shared.start(userId: userId)

        if let aiContext = BackgroundAnalyticsService.shared.cachedAIContext(userId: userId) {
            brain.personalizationContext = UserCalibrationStore.combinedPersonalizationBlock(
                analyticsBlock: aiContext.promptBlock
            )
        }

        inboxVM.onCreateTask = { [weak self] draft in
            guard let self else { return }
            try await self.tasksVM.createFromInbox(draft, userId: userId)
        }

        if healthSync.isHealthEnabled {
            healthSync.startHealthObservers()
        }

        Task {
            await ensureFlowDirector()

            if UserLifeProfileStore.hasCompletedOnboarding, healthSync.isHealthEnabled {
                HealthSummaryRepository().migrateAllSummariesToCanonicalUserId()
                await healthSync.ensureSynced(userId: userId)
            }

            async let brainLoad: Void = orchestrateBrain(userId: userId)
            async let taskLoad: Void = tasksVM.loadTasks(userId: userId)
            async let moduleLoad: Void = modulesVM.loadAllData(userId: userId)
            async let inboxLoad: Void = inboxVM.loadItems(userId: userId)
            _ = await (brainLoad, taskLoad, moduleLoad, inboxLoad)
            await compileLifeModelIfNeeded()
            if let lifeModel = LifeModelStore.load(), lifeModel.hasContent {
                await tasksVM.dedupeLifeCommitmentTasks(userId: userId, model: lifeModel)
                await tasksVM.ensureLifeCommitmentTasks(userId: userId, model: lifeModel)
                await tasksVM.reconcileTodaySchedule(userId: userId, model: lifeModel)
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
            WidgetSyncService.shared.sync(brainVM: brainVM, tasksVM: tasksVM)

            let userName = UserLifeProfileStore.resolvedDisplayName()
            await refreshContext(
                userId: userId,
                userName: userName,
                peakStartHour: UserLifeProfileStore.load().peakStartHour
            )
            startContextLoop(userId: userId)
        }
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
        if !userId.isEmpty { return userId }
        return FirebaseManager.shared.resolvedUserId
    }

    private var contextLoopTask: Task<Void, Never>?

    /// Keeps brain/timeline fresh while the app is open. Capacity stays deterministic — no LLM polling.
    func startContextLoop(userId: String) {
        contextLoopTask?.cancel()
        contextLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard let self, !Task.isCancelled, !self.isPerformingFactoryReset else { return }
                let userName = UserLifeProfileStore.resolvedDisplayName()
                await self.refreshContext(
                    userId: userId,
                    userName: userName,
                    peakStartHour: UserLifeProfileStore.load().peakStartHour,
                    capacityLLMPolicy: .deterministicOnly
                )
            }
        }
    }

    func refreshWidgetData() {
        WidgetSyncService.shared.sync(brainVM: brainVM, tasksVM: tasksVM)
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
        let uid = resolvedUserId(userId)
        guard !uid.isEmpty else { return }
        let resolvedName = userName.isEmpty ? UserLifeProfileStore.resolvedDisplayName() : userName
        await tasksVM.syncRecurringSchedule(userId: uid)
        await orchestrateBrain(userId: uid)
        let shoppingCount = modulesVM.shoppingItems.filter { !$0.isPurchased }.count
        let bills = modulesVM.bills.filter { !$0.isPaid }
        let medications = MedicationStore.load()
        let lifeEvents = ExecutiveTimelineBuilder.buildLifeEvents(
            tasks: tasksVM.tasks,
            completedToday: tasksVM.completedToday,
            recurrenceTemplates: tasksVM.recurrenceTemplates,
            bills: modulesVM.bills,
            shoppingItems: modulesVM.shoppingItems,
            contacts: modulesVM.contacts,
            medications: medications
        )
        let tomorrowEvents = ExecutiveTimelineBuilder.buildTomorrowLifeEvents(
            tasks: tasksVM.tasks,
            recurrenceTemplates: tasksVM.recurrenceTemplates,
            bills: modulesVM.bills,
            shoppingItems: modulesVM.shoppingItems,
            contacts: modulesVM.contacts
        )
        let timeline = lifeEvents
        let isWeekend = Calendar.current.isDateInWeekend(Date())
        await contextOrchestrator.refresh(
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
            peakStartHour: peakStartHour,
            allTasks: tasksVM.tasks,
            completedTaskIDs: Set(tasksVM.completedToday.map(\.id)),
            flowConfidenceScore: brainVM.flowSurface?.confidence,
            capacityLLMPolicy: capacityLLMPolicy
        )
        briefingVM.updateGreeting(
            userName: resolvedName,
            flowSurface: brainVM.flowSurface,
            heroBriefing: contextOrchestrator.briefing?.hero
        )
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
            lifeTimelineEvents: contextOrchestrator.lifeTimelineEvents,
            tomorrowLifeTimelineEvents: contextOrchestrator.tomorrowLifeTimelineEvents
        )
        briefingVM.updateExecutiveCapacity(contextOrchestrator.executiveCapacity)
        refreshWidgetData()

        brainVM.syncFromOrchestrator(
            heroBriefing: contextOrchestrator.briefing?.hero,
            resumeSnapshot: contextOrchestrator.resumeSnapshot,
            executiveCapacity: contextOrchestrator.executiveCapacity,
            lifeSnapshot: contextOrchestrator.snapshot,
            activeTasks: tasksVM.tasks.filter(\.status.isActive),
            upcomingBills: bills,
            medications: medications,
            timelineItems: timeline,
            readinessLabel: briefingVM.healthSnapshot.readinessLabel
        )

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

    private var healthKitEnabled: Bool {
        (UserDefaults.standard.object(forKey: "enableHealth") as? Bool ?? true) && HealthManager().isAvailable
    }

    /// Erases every persisted layer and reboots the app like a fresh install (API keys preserved).
    func performFactoryReset(userId: String, healthSync: HealthSyncService) async {
        isPerformingFactoryReset = true
        contextLoopTask?.cancel()
        contextLoopTask = nil
        BackgroundAnalyticsScheduler.shared.stop()
        BackgroundAnalyticsService.shared.resetForFactoryReset()

        FactoryResetManager.shared.performLocalReset(userId: userId)
        clearInMemoryState(userId: userId)
        healthSync.resetForFactoryReset()
        LiveActivityManager.shared.endAllActivities()
        refreshWidgetData()
        factoryResetGeneration += 1

        await FactoryResetManager.shared.resetCloudIfAvailable()
        await bootstrapFreshStart(userId: userId, healthSync: healthSync)
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
        refreshWidgetData()

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
        brainVM.resetForFactoryReset()
        contextOrchestrator.resetInMemoryState()
        tasksVM.tasks = []
        tasksVM.completedToday = []
        modulesVM.resetInMemoryState()
        inboxVM.resetInMemoryState()
        briefingVM.resetAfterDeveloperWipe()
        adhdVM.endFocusSession()
        continueSession.endSession()
        flowDirector = nil
        flowDirectorUserName = ""
        ResumeEngine.shared.clear(userId: userId)
        PostWakeSessionStore.resetForFactoryReset()
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
}
