import SwiftUI
import LookAfterCore
import LookAfterAI
import LookAfterData
import LookAfterFeatures
import LookAfterHealth

/// LifeOS WWDC Root Canvas — The Zero-Surface Ambient Cognitive OS.
public struct LookAfterRootCanvas: View {
    @EnvironmentObject private var shell: AppShellState
    @EnvironmentObject private var featureTour: AppFeatureTourCoordinator
    @State private var showModules = false
    @State private var showCoach = false
    @State private var showDailyPlan = false
    @State private var showTasks = false
    @State private var showInsights = false
    @State private var showDecideForMe = false
    @State private var decideForMeResult: DecideForMeResult?
    @State private var isLoadingDecideForMe = false
    @State private var showResetMode = false
    @State private var showAuth = false
    @State private var showSettings = false
    @State private var showHealthDetail = false
    @State private var showMedication = false
    @State private var showFullTimeline = false
    @State private var showBrainCapture = false
    @State private var showInbox = false
    @State private var showWelcomeToast = false
    @State private var welcomeToastMessage = ""
    @AppStorage(FlowDirectorFeature.userDefaultsKey) private var enableFlowDirector = false

    @StateObject private var firebase = FirebaseManager.shared
    @StateObject private var healthSync = HealthSyncService.shared
    @StateObject private var weatherService = WeatherDisplayService()
    @StateObject private var speechManager = SpeechRecognitionManager()
    @StateObject private var planningVM = ExecutivePlanningViewModel()
    @StateObject private var tomorrowPlannerVM = DailyPlannerViewModel()
    @StateObject private var planningSpeech = PlanningSpeechSynthesizer()
    @ObservedObject private var notificationRouter = NotificationRouter.shared
    @State private var selectedTab: LookAfterTab = .briefing
    @State private var tabBeforeFocus: LookAfterTab = .briefing
    @State private var showTomorrowPlanPreview = false

    public init() {}

    private var heroTask: LifeTask? {
        if let id = shell.contextOrchestrator.briefing?.hero.action.taskID,
           let task = shell.tasksVM.tasks.first(where: { $0.id == id }) {
            return task
        }
        return shell.brainVM.flowSurface?.heroTask ?? shell.brainVM.topTasks.first
    }

    private var briefingHeroInput: BriefingProjectorInput {
        BriefingProjectorInput(
            userName: UserLifeProfileStore.resolvedDisplayName(),
            heroBriefing: shell.contextOrchestrator.briefing?.hero,
            brainDecision: shell.contextOrchestrator.brainState?.decision,
            flowSurface: shell.brainVM.flowSurface,
            recommendation: shell.brainVM.recommendation,
            topTasks: shell.brainVM.topTasks,
            resumeSnapshot: shell.contextOrchestrator.resumeSnapshot,
            executiveCapacity: shell.contextOrchestrator.executiveCapacity,
            lifeSnapshot: shell.contextOrchestrator.snapshot,
            cognitiveSnapshot: shell.brainVM.cognitiveSnapshot,
            healthSummary: shell.brainVM.healthSummary,
            activeTasks: shell.tasksVM.tasks.filter(\.status.isActive),
            upcomingBills: shell.modulesVM.bills.filter { !$0.isPaid },
            medications: MedicationStore.load(),
            timelineItems: shell.timelineService.snapshot.today
        )
    }

    private var heroDisplay: BriefingHeroDisplayContent {
        BriefingProjector.heroDisplayContent(
            from: briefingHeroInput,
            peakFocusWindow: shell.briefingVM.energy.peakFocusWindow
        )
    }

    private var calmHeroContent: CalmHeroContent {
        if let hero = shell.contextOrchestrator.briefing?.hero {
            return CalmHeroContentBuilder.from(
                title: heroDisplay.title,
                buttonLabel: heroDisplay.buttonLabel,
                greeting: hero.greeting,
                contextLine: hero.contextLine,
                outcomeLine: hero.outcomeLine,
                whyLine: heroDisplay.whyLine,
                durationLabel: heroDisplay.durationLabel,
                windowLabel: heroDisplay.windowLabel,
                narrative: heroDisplay.subtitle,
                skipConsequence: nil,
                alternativePrompt: hero.lowConfidencePrompt,
                whyNowReasons: hero.whyNowReasons
            )
        }
        return CalmHeroContentBuilder.from(
            title: heroDisplay.title,
            buttonLabel: heroDisplay.buttonLabel,
            whyLine: heroDisplay.whyLine,
            durationLabel: heroDisplay.durationLabel,
            windowLabel: heroDisplay.windowLabel,
            narrative: heroDisplay.subtitle
        )
    }

    private var showsBottomNav: Bool {
        !shell.adhdVM.isEmergencyMode
            && !shell.adhdVM.isFocusSessionActive
            && !shell.adhdVM.isCountdownActive
            && !shell.adhdVM.isBodyDoubling
    }

    public var body: some View {
        ZStack {
            PremiumBackground()

            tabContent
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if showsBottomNav {
                        LookAfterBottomNav(selection: $selectedTab, onCapture: { showBrainCapture = true })
                    }
                }

            // ADHD Overlays
            if shell.adhdVM.isEmergencyMode {
                EmergencyModeView(adhdVM: shell.adhdVM) { task in
                    shell.adhdVM.startCountdown(for: task) {
                        shell.adhdVM.startFocusSession(task: task)
                    }
                }
                .transition(.opacity)
                .zIndex(100)
                VStack {
                    Spacer()
                    ADHDFloatingDockView(
                        onDecideForMe: { showDecideForMe = true },
                        onVoiceCapture: { showCoach = true },
                        onResetMode: { showResetMode = true }
                    )
                    .padding(.bottom, 12)
                }
            }

            if shell.adhdVM.isFocusSessionActive {
                FocusSessionView(adhdVM: shell.adhdVM)
                    .zIndex(99)
                    .ignoresSafeArea()
            }

            if shell.adhdVM.isBodyDoubling {
                BodyDoublingView(adhdVM: shell.adhdVM)
                    .transition(.opacity)
                    .zIndex(98)
            }

            if shell.adhdVM.isCountdownActive {
                TaskInitiationView(adhdVM: shell.adhdVM)
                    .transition(.scale)
                    .zIndex(101)
            }

            if healthSync.isConnectingForSetup || shell.isBootstrappingFreshStart {
                VStack {
                    HealthSyncProgressView(healthSync: healthSync, style: .compact)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(90)
                .allowsHitTesting(false)
            }

            if featureTour.isActive {
                AppFeatureTourOverlay(coordinator: featureTour)
                    .zIndex(200)
            }
        }
        .onChange(of: featureTour.requestedTab) { _, tab in
            guard let tab else { return }
            selectedTab = tab
        }
        .onChange(of: featureTour.stepIndex) { _, _ in
            if let tab = featureTour.requestedTab {
                selectedTab = tab
            }
        }
        .sheet(isPresented: $showModules) {
            AllModulesGridView(modulesVM: shell.modulesVM, userId: firebase.resolvedUserId)
                .environmentObject(shell)
        }
        .sheet(isPresented: $showCoach) {
            AICoachView(brain: shell.brain)
        }
        .sheet(isPresented: $showDailyPlan) {
            DailyPlanView(userId: firebase.resolvedUserId)
        }
        .sheet(isPresented: $showFullTimeline) {
            NavigationStack {
                ScrollView {
                    ExecutiveLiveTimelineView(
                        rows: planningVM.timelineRows,
                        thinkingStep: planningVM.visibleThinkingStep,
                        isProcessing: planningVM.isProcessing,
                        title: "Full timeline",
                        onViewAll: { showFullTimeline = false },
                        onCompleteTask: { taskId in
                            Task { await completeTimelineTask(taskId: taskId) }
                        },
                        onUncompleteTask: { taskId in
                            Task { await uncompleteTimelineTask(taskId: taskId) }
                        },
                        onStartTask: { taskId in
                            if let task = resolveTimelineTask(id: taskId) {
                                showFullTimeline = false
                                startBrainHeroTask(task, instant: true)
                            }
                        },
                        onEditTask: { taskId in
                            if let task = resolveTimelineTask(id: taskId) {
                                shell.tasksVM.selectedTask = task
                                showFullTimeline = false
                                showTasks = true
                            }
                        },
                        onRescheduleTask: { taskId in
                            Task { await rescheduleTimelineTask(taskId: taskId) }
                        }
                    )
                    .padding(.horizontal, DesignSystem.BriefingViewport.sectionHorizontal)
                    .padding(.vertical, DesignSystem.spacingMD)
                }
                .background(PremiumBackground())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showFullTimeline = false }
                    }
                }
            }
            .environmentObject(shell)
        }
        .sheet(isPresented: $showTasks) {
            TaskListView(
                tasksVM: shell.tasksVM,
                adhdVM: shell.adhdVM,
                brainVM: shell.brainVM,
                userId: firebase.resolvedUserId
            )
        }
        .sheet(isPresented: $showInsights) {
            InsightsDashboardView(brain: shell.brain, userId: firebase.resolvedUserId)
        }
        .sheet(isPresented: $showDecideForMe) {
            if let result = decideForMeResult {
                DecideForMeView(task: result.task, reason: result.reason, adhdVM: shell.adhdVM)
            } else if isLoadingDecideForMe {
                ProgressView("Finding your one task…")
                    .padding()
            } else if let topTask = heroTask {
                DecideForMeView(task: topTask, adhdVM: shell.adhdVM)
            }
        }
        .onChange(of: showDecideForMe) { _, show in
            guard show else {
                decideForMeResult = nil
                return
            }
            isLoadingDecideForMe = true
            Task {
                let snapshot = shell.brainVM.cognitiveSnapshot ?? CognitiveSnapshot()
                let tasks = shell.tasksVM.tasks.filter(\.status.isActive)
                let picker = DecideForMePicker()
                let result = await picker.pick(snapshot: snapshot, tasks: tasks)
                await MainActor.run {
                    decideForMeResult = result
                    isLoadingDecideForMe = false
                }
            }
        }
        .sheet(isPresented: $showResetMode) {
            PhysiologicalResetView()
        }
        .sheet(isPresented: $showHealthDetail) {
            HealthDetailView()
                .environmentObject(shell)
        }
        .sheet(isPresented: $showMedication) {
            NavigationStack {
                MedicationView()
            }
        }
        .sheet(isPresented: $showBrainCapture) {
            ExecutiveCaptureSheet(userId: firebase.resolvedUserId, onOpenInbox: {
                showBrainCapture = false
                showInbox = true
            })
                .environmentObject(shell)
        }
        .sheet(isPresented: $showInbox) {
            NavigationStack {
                InboxView(inboxVM: shell.inboxVM, userId: firebase.resolvedUserId)
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .environmentObject(shell)
            }
        }
        .sheet(isPresented: $showTomorrowPlanPreview) {
            if let proposal = tomorrowPlannerVM.rescheduleProposal {
                ReschedulePreviewSheet(
                    plannerVM: tomorrowPlannerVM,
                    proposal: proposal,
                    userId: firebase.resolvedUserId
                )
            }
        }
        .onChange(of: tomorrowPlannerVM.rescheduleProposal?.id) { _, newID in
            showTomorrowPlanPreview = newID != nil
        }
        .onChange(of: showTomorrowPlanPreview) { wasShowing, isShowing in
            if wasShowing && !isShowing {
                Task { await refreshTimelinePage(userId: firebase.resolvedUserId) }
            }
        }
        .fullScreenCover(isPresented: Binding<Bool>(
            get: { !firebase.isAuthenticated },
            set: { _ in }
        )) {
            AuthView()
        }
        .toast(isShowing: $showWelcomeToast, message: welcomeToastMessage, type: .success)
        .onChange(of: firebase.isAuthenticated) { _, authenticated in
            if authenticated {
                showAuth = false
                let name = UserLifeProfileStore.resolvedDisplayName()
                welcomeToastMessage = "Welcome back, \(name.isEmpty ? "there" : name)!"
                withAnimation {
                    showWelcomeToast = true
                }
                HapticManager.notification(.success)
            }
        }
        .onChange(of: enableFlowDirector) { _, _ in
            guard firebase.isAuthenticated else { return }
            Task {
                await orchestrateBrain(userId: firebase.resolvedUserId)
                shell.refreshWidgetData()
            }
        }
        .onChange(of: shell.adhdVM.isFocusSessionActive) { wasActive, isActive in
            if wasActive && !isActive {
                selectedTab = tabBeforeFocus
            }
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .today {
                Task { await weatherService.refresh() }
            }
        }
        .task(id: enableFlowDirector) {
            guard enableFlowDirector, firebase.isAuthenticated else { return }
            await orchestrateBrain(userId: firebase.resolvedUserId)
        }
        .task {
            await weatherService.refresh()
            planningVM.bind(timelineService: shell.timelineService)
            planningVM.onSpeakReply = { text in
                guard SpeechVoiceSettings.autoSpeakReplies else { return }
                planningSpeech.speak(text)
            }
        }
        .onChange(of: shell.factoryResetGeneration) { _, _ in
            planningVM.factoryReset()
        }
        .onChange(of: notificationRouter.pendingRoute) { _, route in
            guard let route else { return }
            switch route {
            case .briefing:
                selectedTab = .briefing
            case .today:
                selectedTab = .today
            case .brain:
                selectedTab = .brain
            case .task:
                selectedTab = .today
                if let taskId = notificationRouter.pendingRoutePayload,
                   let task = shell.tasksVM.tasks.first(where: { $0.id == taskId }) {
                    shell.tasksVM.selectedTask = task
                    showTasks = true
                } else {
                    showTasks = true
                }
            case .medication:
                showMedication = true
            case .focusSession:
                break
            }
            _ = notificationRouter.consumeRoute()
        }
        .accessibilityIdentifier("screen-briefing")
    }

    // MARK: - Tabs

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .briefing:
            DailyBriefingView(
                briefingVM: shell.briefingVM,
                brainVM: shell.brainVM,
                tasksVM: shell.tasksVM,
                healthSync: healthSync,
                userId: firebase.resolvedUserId,
                onOpenToday: { selectedTab = .today },
                onOpenTasks: { showTasks = true },
                onOpenCoach: { showCoach = true },
                onOpenDailyPlan: { showDailyPlan = true },
                onOpenSettings: { showSettings = true },
                onCapture: { showBrainCapture = true },
                onStartTask: { task in startBrainHeroTask(task, instant: true) },
                onReplanDay: { showDailyPlan = true }
            )
        case .today:
            TodayView(
                briefingVM: shell.briefingVM,
                planningVM: planningVM,
                speechManager: speechManager,
                speechSynthesizer: planningSpeech,
                modulesVM: shell.modulesVM,
                tasksVM: shell.tasksVM,
                lifeTimelineEvents: shell.timelineService.snapshot.today,
                tomorrowLifeTimelineEvents: shell.timelineService.snapshot.tomorrow,
                weatherSnapshot: weatherService.snapshot,
                onSettings: {
                    if firebase.isAuthenticated { showSettings = true } else { showAuth = true }
                },
                onOpenTasks: { showTasks = true },
                onViewTimeline: { showFullTimeline = true },
                onReplanDay: { Task { await triggerReplanDay() } },
                onPlanTomorrow: { Task { await triggerPlanTomorrow(userId: firebase.resolvedUserId) } },
                onRefresh: { await refreshTimelinePage(userId: firebase.resolvedUserId) },
                onPlanningSubmit: submitPlanningTurn,
                onNegotiationSelect: { option in
                    Task { await submitPlanningNegotiation(option) }
                },
                onRedesignWithAI: { message in
                    Task { await redesignPlanningWithAI(userMessage: message) }
                },
                onOpenSleepDetail: { showHealthDetail = true },
                onOpenHealthDetail: { showHealthDetail = true },
                onOpenMedication: { showMedication = true },
                onCompleteTimelineTask: { taskId in
                    Task { await completeTimelineTask(taskId: taskId) }
                },
                onUncompleteTimelineTask: { taskId in
                    Task { await uncompleteTimelineTask(taskId: taskId) }
                },
                onRescheduleTimelineTask: { taskId in
                    Task { await rescheduleTimelineTask(taskId: taskId) }
                },
                onStartTask: { task in startBrainHeroTask(task, instant: true) },
                onEditTask: { task in
                    shell.tasksVM.selectedTask = task
                    showTasks = true
                },
                isPlanningTomorrow: tomorrowPlannerVM.isScheduling
            )
        case .review:
            WeeklyReviewView(summary: weeklyReviewSummary)
        case .brain:
            BrainDashboardView(
                brainVM: shell.brainVM,
                adhdVM: shell.adhdVM,
                brain: shell.brain,
                speechManager: speechManager,
                speechSynthesizer: planningSpeech,
                userId: firebase.resolvedUserId,
                onStartHero: { task in startBrainHeroTask(task) },
                onRescheduleHero: { task in
                    Task { await rescheduleBrainHeroTask(task) }
                },
                onDecideForMe: { showDecideForMe = true },
                onCapture: { showBrainCapture = true },
                onResume: { taskID in resumeBrainSession(taskID: taskID) },
                onMarkMedicationTaken: { medID in markBrainMedicationTaken(medID) },
                onNavigateToTasks: { showTasks = true },
                onNavigateToCoach: { showCoach = true },
                onReset: { showResetMode = true },
                onRefresh: {
                    let userId = firebase.resolvedUserId
                    let name = UserLifeProfileStore.resolvedDisplayName()
                    let peak = UserLifeProfileStore.load().peakStartHour
                    await shell.refreshContext(userId: userId, userName: name, peakStartHour: peak)
                }
            )
        case .you:
            ExecutiveProfileView(userId: firebase.resolvedUserId)
        }
    }

    /// Pull cascade history from BehavioralVault-adjacent `CascadeActionLog` via `LifeEngine`.
    private var weeklyReviewSummary: WeeklyReviewSummary {
        let tasks = shell.taskStore.allTasks.isEmpty ? shell.tasksVM.tasks : shell.taskStore.allTasks
        return LifeEngine.shared.weeklyReview(tasks: tasks)
    }

    private func activeFlowSessionState() -> FlowSessionState? {
        guard shell.adhdVM.isFocusSessionActive, let task = shell.adhdVM.currentFocusTask else { return nil }
        return FlowSessionState(
            isActive: true,
            taskID: task.id,
            elapsedSeconds: Int(shell.adhdVM.focusSessionElapsed),
            targetSeconds: Int(shell.adhdVM.focusSessionTarget),
            isPaused: shell.adhdVM.isPaused,
            isResting: shell.adhdVM.isOnBreak
        )
    }

    private func orchestrateBrain(userId: String) async {
        await shell.ensureFlowDirector()
        await shell.brainVM.refresh(userId: userId, activeFlowSession: activeFlowSessionState())
        if shell.brainVM.isUsingFlowDirector, let surface = shell.brainVM.flowSurface {
            FlowDirectorIntegrationLog.recordOrchestration(
                surface: surface,
                durationMs: shell.brainVM.lastOrchestrationDurationMs
            )
        }
    }

    private func triggerReplanDay() async {
        let userId = firebase.resolvedUserId
        let context = planningContext()
        let sleepHours = shell.brainVM.healthSummary?.totalSleepMinutes.map { $0 / 60.0 }
        let goals = UserDefaults.standard.string(forKey: "userKeyGoals")
        let replanContext = DayReplanContext(
            planningContext: context,
            completedTasks: shell.tasksVM.completedToday,
            weatherSummary: weatherService.snapshot.chipSecondary,
            sleepHours: sleepHours,
            userGoals: goals
        )
        await planningVM.replanDay(
            context: replanContext,
            tasksVM: shell.tasksVM,
            modulesVM: shell.modulesVM,
            userId: userId,
            refreshContext: { [shell] in
                let name = UserLifeProfileStore.resolvedDisplayName()
                let peak = UserLifeProfileStore.load().peakStartHour
                await shell.refreshContext(
                    userId: userId,
                    userName: name,
                    peakStartHour: peak
                )
                await MainActor.run {
                    planningVM.refreshTimeline(from: shell.timelineService.snapshot.today)
                }
            }
        )
    }

    private func planningContext() -> PlanningConversationContext {
        let userName = UserLifeProfileStore.resolvedDisplayName()
        let userId = firebase.resolvedUserId
        let analytics = BackgroundAnalyticsService.shared.cachedAIContext(userId: userId)
        return ExecutivePlanningViewModel.buildContext(
            userName: userName.isEmpty ? "there" : userName,
            tasksVM: shell.tasksVM,
            timelineItems: shell.timelineService.snapshot.today,
            snapshot: shell.contextOrchestrator.snapshot,
            healthSummary: shell.brainVM.healthSummary,
            executiveCapacity: shell.contextOrchestrator.executiveCapacity,
            analyticsContext: analytics
        )
    }

    private func submitPlanningTurn(text: String, startedWithVoice: Bool) {
        let userId = firebase.resolvedUserId
        let context = planningContext()
        Task {
            await planningVM.submit(
                text: text,
                startedWithVoice: startedWithVoice,
                context: context,
                tasksVM: shell.tasksVM,
                modulesVM: shell.modulesVM,
                userId: userId,
                refreshContext: planningRefreshContext(userId: userId)
            )
        }
    }

    private func redesignPlanningWithAI(userMessage: String) async {
        let userId = firebase.resolvedUserId
        let context = planningContext()
        await planningVM.redesignWithAI(
            userMessage: userMessage,
            context: context,
            tasksVM: shell.tasksVM,
            modulesVM: shell.modulesVM,
            userId: userId,
            refreshContext: planningRefreshContext(userId: userId)
        )
    }

    private func refreshTimelinePage(userId: String) async {
        let name = UserLifeProfileStore.resolvedDisplayName()
        let peak = UserLifeProfileStore.load().peakStartHour
        await shell.tasksVM.loadTasks(userId: userId)
        if LifeModelStore.hasCompiledModel {
            await shell.assembleTomorrowFromLifeModel(userId: userId)
        }
        await shell.refreshContext(
            userId: userId,
            userName: name,
            peakStartHour: peak
        )
    }

    private func triggerPlanTomorrow(userId: String) async {
        guard !userId.isEmpty else { return }
        await shell.assembleTomorrowFromLifeModel(userId: userId)
        await refreshTimelinePage(userId: userId)
        let healthContext = BackgroundAnalyticsService.shared.cachedAIContext(userId: userId)?.promptBlock
        await tomorrowPlannerVM.proposeTomorrowReschedule(userId: userId, healthContext: healthContext)
    }

    private func resolveTimelineTask(id: String) -> LifeTask? {
        shell.tasksVM.resolveTimelineTask(id: id)
    }

    private func completeTimelineTask(taskId: String) async {
        let userId = firebase.resolvedUserId
        guard !userId.isEmpty else { return }
        let titleHint = planningVM.timelineRows.first(where: { $0.taskId == taskId })?.title

        HapticManager.notification(.success)
        guard await shell.tasksVM.completeTimelineTask(id: taskId, userId: userId, titleHint: titleHint) != nil else {
            print("[Tasks] completeTimelineTask missed taskId=\(taskId.prefix(8))")
            return
        }
        planningVM.markTimelineTaskCompleted(taskId: taskId)
        shell.rebuildTimelineFromTasks()
        planningVM.refreshTimeline(from: shell.timelineService.snapshot.today)
        shell.refreshWidgetData()
    }

    private func uncompleteTimelineTask(taskId: String) async {
        let userId = firebase.resolvedUserId
        guard !userId.isEmpty else { return }
        let titleHint = planningVM.timelineRows.first(where: { $0.taskId == taskId })?.title

        HapticManager.impact(.light)
        guard await shell.tasksVM.uncompleteTimelineTask(id: taskId, userId: userId, titleHint: titleHint) else {
            print("[Tasks] uncompleteTimelineTask missed taskId=\(taskId.prefix(8))")
            return
        }
        planningVM.markTimelineTaskUncompleted(taskId: taskId)
        shell.rebuildTimelineFromTasks()
        planningVM.refreshTimeline(from: shell.timelineService.snapshot.today)
        shell.refreshWidgetData()
    }

    private func rescheduleTimelineTask(taskId: String) async {
        let userId = firebase.resolvedUserId
        guard !userId.isEmpty,
              let task = shell.tasksVM.tasks.first(where: { $0.id == taskId && $0.status.isActive }) else {
            return
        }
        guard let newTime = await shell.tasksVM.rescheduleTaskFromNow(task) else { return }
        HapticManager.impact(.medium)
        planningVM.markTimelineTaskRescheduled(taskId: taskId, to: newTime)
        await refreshTimelinePage(userId: userId)
    }

    private func startBrainHeroTask(_ task: LifeTask?, instant: Bool = false) {
        if let task {
            tabBeforeFocus = selectedTab
            if instant {
                shell.adhdVM.startFocusSession(task: task)
            } else {
                shell.adhdVM.startCountdown(for: task) {
                    shell.adhdVM.startFocusSession(task: task)
                }
            }
            return
        }
        showBrainCapture = true
    }

    private func resumeBrainSession(taskID: String?) {
        let resolved = taskID.flatMap { id in
            shell.tasksVM.tasks.first { $0.id == id && $0.status.isActive }
        } ?? heroTask
        startBrainHeroTask(resolved)
    }

    private func rescheduleBrainHeroTask(_ task: LifeTask) async {
        let userId = firebase.resolvedUserId
        guard !userId.isEmpty else { return }
        guard await shell.tasksVM.rescheduleTaskFromNow(task) != nil else { return }
        HapticManager.impact(.medium)
        let name = UserLifeProfileStore.resolvedDisplayName()
        let peak = UserLifeProfileStore.load().peakStartHour
        await shell.refreshContext(userId: userId, userName: name, peakStartHour: peak)
    }

    private func markBrainMedicationTaken(_ medicationID: String) {
        var medications = MedicationStore.load()
        guard let index = medications.firstIndex(where: { $0.id == medicationID }) else { return }
        medications[index].isTaken = true
        medications[index].lastTakenAt = Date()
        medications[index].adherenceLog.append(Date())
        MedicationStore.save(medications)
        HapticManager.notification(.success)
        Task {
            let userId = firebase.resolvedUserId
            let name = UserLifeProfileStore.resolvedDisplayName()
            let peak = UserLifeProfileStore.load().peakStartHour
            await shell.refreshContext(userId: userId, userName: name, peakStartHour: peak)
        }
    }

    private func planningRefreshContext(userId: String) -> () async -> Void {
        {
            await refreshTimelinePage(userId: userId)
        }
    }

    private func submitPlanningNegotiation(_ option: String) async {
        let userId = firebase.resolvedUserId
        let context = planningContext()
        await planningVM.selectNegotiationOption(
            option,
            context: context,
            tasksVM: shell.tasksVM,
            modulesVM: shell.modulesVM,
            userId: userId,
            refreshContext: planningRefreshContext(userId: userId)
        )
    }
}
