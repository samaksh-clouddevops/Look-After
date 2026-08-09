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
    @State private var taskListInitialFilter: TaskFilter = .all
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
    @State private var fullTimelineScrollDisabled = false
    @State private var showBrainCapture = false
    @State private var showInbox = false
    @State private var captureSource: CaptureSource = .bottomNav
    @State private var captureContextHints = CaptureContextHints()
    @State private var showCaptureToast = false
    @State private var captureToastMessage = ""
    @State private var captureUndoTaskId: String?
    @State private var captureUndoInboxId: String?
    @State private var captureViewAction: (() -> Void)?
    @State private var captureViewLabel = "View"
    @State private var lastFocusedTaskId: String?
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
    @State private var weeklyReviewSummaryCache: WeeklyReviewSummary?
    @State private var weeklyAIRetrospective: WeeklyAIRetrospective?
    @State private var accountabilityShareMessage = ""
    @State private var showAccountabilityShare = false
    @State private var weeklyReviewManualRefreshGeneration = 0
    @State private var showPostWakeSheet = false
    @State private var showGoingOutSheet = false
    @State private var showContextualReplanPreview = false

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
        canvasWithChrome
    }

    private var mainCanvasStack: some View {
        ZStack {
            PremiumBackground()

            tabContent
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if showsBottomNav {
                        LookAfterBottomNav(selection: $selectedTab, onCapture: { openCapture(source: .bottomNav) })
                    }
                }

            // ADHD overlays observe adhdVM in a child — not the full shell (PERF-019).
            ADHDOverlayHost(
                adhdVM: shell.adhdVM,
                onDecideForMe: { showDecideForMe = true },
                onVoiceCapture: { showCoach = true },
                onResetMode: { showResetMode = true }
            )

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
    }

    @ViewBuilder
    private var canvasWithChrome: some View {
        mainCanvasStack
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
            fullTimelineSheet
        }
        .sheet(isPresented: $showTasks) {
            TaskListView(
                tasksVM: shell.tasksVM,
                adhdVM: shell.adhdVM,
                brainVM: shell.brainVM,
                userId: firebase.resolvedUserId,
                initialFilter: taskListInitialFilter
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
            HealthDetailView(
                userId: firebase.resolvedUserId,
                onLogMood: {
                    showHealthDetail = false
                    openCapture(
                        source: .healthDetail,
                        hints: CaptureContextHints(screen: "healthDetail", preselectedIntent: .mood)
                    )
                }
            )
            .environmentObject(shell)
        }
        .sheet(isPresented: $showMedication) {
            NavigationStack {
                MedicationView()
            }
        }
        .sheet(isPresented: $showBrainCapture) {
            ExecutiveCaptureSheet(
                userId: firebase.resolvedUserId,
                source: captureSource,
                contextHints: captureContextHints,
                onOpenInbox: {
                    showBrainCapture = false
                    showInbox = true
                },
                onRouted: handleCaptureRouted
            )
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
        .modifier(
            ContextualReplanSheetsModifier(
                showPostWakeSheet: $showPostWakeSheet,
                showGoingOutSheet: $showGoingOutSheet,
                showContextualReplanPreview: $showContextualReplanPreview,
                suggestedWakeTime: shell.brainVM.healthSummary?.wakeTime,
                planningVM: planningVM,
                taskTitles: contextualReplanTaskTitles,
                userId: firebase.resolvedUserId,
                onPostWakeSubmit: submitPostWakeReplan,
                onGoingOutSubmit: submitGoingOutReplan
            )
        )
        .sheet(isPresented: $shell.showManualSleepSheet) {
            ManualSleepSheet(
                onSubmit: { rating in
                    Task {
                        await shell.submitManualSleep(rating, userId: firebase.resolvedUserId)
                    }
                },
                onSkip: {
                    shell.dismissManualSleepPromptForToday()
                }
            )
        }
        .sheet(isPresented: $showAccountabilityShare) {
            ActivityView(activityItems: [accountabilityShareMessage])
        }
        .onChange(of: notificationRouter.pendingSpeakBody) { _, body in
            guard let body else { return }
            ProactiveSpeechService(synthesizer: planningSpeech).speakNotificationBody(body)
            notificationRouter.pendingSpeakBody = nil
        }
        .sheet(isPresented: $shell.showInitiationScriptSheet) {
            if let script = shell.pendingInitiationScript {
                InitiationScriptSheet(
                    script: script,
                    speechSynthesizer: planningSpeech,
                    onStartFocus: {
                        if let task = shell.tasksVM.tasks.first(where: { $0.id == script.taskID }) {
                            tabBeforeFocus = selectedTab
                            shell.adhdVM.startFocusSession(task: task, durationMinutes: script.durationMinutes)
                        }
                        shell.showInitiationScriptSheet = false
                    },
                    onDismiss: {
                        shell.showInitiationScriptSheet = false
                        shell.pendingInitiationScript = nil
                    }
                )
                .environmentObject(shell)
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
        .onChange(of: shell.pendingCalendarChange?.summaryLine) { _, summary in
            guard summary != nil else { return }
            Task { await triggerCalendarChangeReplan() }
        }
        .onChange(of: planningVM.contextualReplanResult?.summary) { _, summary in
            if summary != nil, planningVM.contextualReplanTrigger == .calendarChange {
                showContextualReplanPreview = true
            }
        }
        .fullScreenCover(isPresented: Binding<Bool>(
            get: { !firebase.isAuthenticated },
            set: { _ in }
        )) {
            AuthView()
        }
        .toast(isShowing: $showWelcomeToast, message: welcomeToastMessage, type: .success)
        .undoToast(
            isShowing: $showCaptureToast,
            message: captureToastMessage,
            duration: 5,
            showsUndo: captureUndoTaskId != nil,
            onUndo: undoLastCapture,
            onView: captureViewAction,
            viewLabel: captureViewLabel,
            onDismiss: {
                captureUndoTaskId = nil
                captureUndoInboxId = nil
                captureViewAction = nil
            }
        )
        .onReceive(NotificationCenter.default.publisher(for: .captureDidRoute)) { note in
            if let box = note.userInfo?[CaptureNotificationKey.result] as? CaptureRouteResultBox {
                handleCaptureRouted(box.result)
            }
        }
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    openCapture(
                        source: .postFocus,
                        hints: CaptureContextHints(
                            screen: "postFocus",
                            activeTaskId: lastFocusedTaskId,
                            preselectedIntent: .note
                        )
                    )
                }
            } else if !wasActive && isActive {
                lastFocusedTaskId = shell.adhdVM.currentFocusTask?.id
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
            bindPlanningSpeechHandler()
        }
        .onChange(of: shell.factoryResetGeneration) { _, _ in
            if featureTour.isActive {
                featureTour.complete()
            }
            selectedTab = .briefing
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
                    openTaskList()
                } else {
                    openTaskList()
                }
            case .medication:
                showMedication = true
            case .focusSession:
                selectedTab = .brain
            case .emergency:
                selectedTab = .briefing
            case .capture:
                if let text = notificationRouter.pendingRoutePayload, !text.isEmpty {
                    captureSource = .shortcuts
                    captureContextHints = CaptureContextHints(screen: "shortcuts")
                    showBrainCapture = true
                } else {
                    openCapture(source: .shortcuts, hints: CaptureContextHints(screen: "shortcuts"))
                }
            }
            _ = notificationRouter.consumeRoute()
            if let body = notificationRouter.consumeSpeakBody() {
                ProactiveSpeechService(synthesizer: planningSpeech).speakNotificationBody(body)
            }
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
                onOpenTasks: { openTaskList() },
                onOpenCoach: { showCoach = true },
                onOpenDailyPlan: { showDailyPlan = true },
                onOpenSettings: { showSettings = true },
                onCapture: { openCapture(source: .briefing, hints: CaptureContextHints(screen: "briefing")) },
                onStartTask: { task in startBrainHeroTask(task, instant: true) },
                onReplanDay: { showDailyPlan = true },
                onPostWake: { showPostWakeSheet = true },
                isPostWake: shell.briefingVM.isPostWake,
                onDismissPostWake: { shell.briefingVM.dismissPostWakeForToday() }
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
                onOpenTasks: { openTaskList() },
                onViewTimeline: { showFullTimeline = true },
                onReplanDay: { Task { await triggerReplanDay() } },
                onPlanTomorrow: { Task { await triggerPlanTomorrow(userId: firebase.resolvedUserId) } },
                onPostWake: { showPostWakeSheet = true },
                onGoingOut: { showGoingOutSheet = true },
                onRefresh: { await refreshTimelinePage(userId: firebase.resolvedUserId) },
                onPlanningSubmit: submitPlanningTurn,
                onNegotiationSelect: { option in
                    Task { await handleProactiveNegotiation(option) }
                },
                onProactiveBannerAppear: { action in
                    ProactiveSpeechService(synthesizer: planningSpeech).speakProactiveAction(action)
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
                onRemoveFromTimelineTask: { taskId in
                    Task { await removeFromTimelineAndReplanSlot(taskId: taskId) }
                },
                onStartTask: { task in startBrainHeroTask(task, instant: true) },
                onEditTask: { task in
                    shell.tasksVM.selectedTask = task
                    openTaskList()
                },
                onCapture: {
                    openCapture(
                        source: .todayTimeline,
                        hints: CaptureContextHints(screen: "todayTimeline")
                    )
                },
                isPlanningTomorrow: tomorrowPlannerVM.isScheduling
            )
        case .review:
            WeeklyReviewView(
                summary: displayedWeeklyReviewSummary,
                aiRetrospective: weeklyAIRetrospective,
                onRefresh: { await refreshWeeklyReview() }
            )
            .id(weeklyReviewRefreshKey)
            .onChange(of: weeklyReviewRefreshKey) { _, _ in
                recomputeWeeklyReviewSummary()
            }
            .onAppear {
                recomputeWeeklyReviewSummary()
            }
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
                onCapture: { openCapture(source: .brain, hints: CaptureContextHints(screen: "brain")) },
                onResume: { taskID in resumeBrainSession(taskID: taskID) },
                onMarkMedicationTaken: { medID in markBrainMedicationTaken(medID) },
                onNavigateToTasks: { openTaskList() },
                onNavigateToCoach: { showCoach = true },
                onReset: { showResetMode = true },
                onRefresh: {
                    let userId = firebase.resolvedUserId
                    let name = UserLifeProfileStore.resolvedDisplayName()
                    let peak = UserLifeProfileStore.load().peakStartHour
                    await shell.refreshContext(userId: userId, userName: name, peakStartHour: peak)
                },
                onExecutivePlan: { message in
                    await submitPlanningTurnAndGetReply(text: message, startedWithVoice: true)
                },
                hasPriorVoiceConversation: !planningVM.turns.isEmpty
            )
        case .you:
            ExecutiveProfileView(userId: firebase.resolvedUserId)
        }
    }

    /// Tasks for weekly metrics — always uses live scheduling context.
    private var weeklyReviewTasks: [LifeTask] {
        shell.tasksVM.schedulingContext
    }

    /// Bumps when task or cascade data changes so the Review tab refreshes.
    private var weeklyReviewRefreshKey: String {
        let tasks = weeklyReviewTasks
        let completed = tasks.filter { $0.status == .completed }.count
        return "review-\(tasks.count)-\(completed)-\(LifeEngine.shared.behavioralVaultHistory.count)-\(weeklyReviewManualRefreshGeneration)"
    }

    private var displayedWeeklyReviewSummary: WeeklyReviewSummary {
        weeklyReviewSummaryCache ?? LifeEngine.shared.weeklyReview(tasks: weeklyReviewTasks)
    }

    private func recomputeWeeklyReviewSummary() {
        weeklyReviewSummaryCache = LifeEngine.shared.weeklyReview(tasks: weeklyReviewTasks)
    }

    private func refreshWeeklyReview() async {
        shell.tasksVM.syncFromTaskStore()
        weeklyReviewManualRefreshGeneration += 1
        recomputeWeeklyReviewSummary()
        let behavior = await ProactiveActionsBuilder.loadBehaviorMemory()
        let analytics = BackgroundAnalyticsService.shared.cachedAIContext(userId: firebase.resolvedUserId)
        weeklyAIRetrospective = await WeeklyAIRetrospectiveGenerator().generate(
            summary: displayedWeeklyReviewSummary,
            analytics: analytics,
            behaviorMemory: behavior
        )
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

    private var contextualReplanTaskTitles: [String: String] {
        Dictionary.uniquingFirstValue(shell.tasksVM.tasks.map { ($0.id, $0.title) })
    }

    private func submitPostWakeReplan(wakeTime: Date) async {
        PostWakeSessionStore.recordExplicitWake(at: wakeTime)
        let constraint = UserDayConstraint.postWake(wakeTime: wakeTime)
        UserDayConstraintStore.set(constraint)
        await triggerContextualReplan(trigger: .postWake, constraint: constraint)
    }

    private func submitGoingOutReplan(departure: Date, durationMinutes: Int) async {
        let constraint = UserDayConstraint.goingOut(departure: departure, durationMinutes: durationMinutes)
        UserDayConstraintStore.set(constraint)
        await triggerContextualReplan(trigger: .goingOut, constraint: constraint)
    }

    private func triggerContextualReplan(trigger: DayReplanTrigger, constraint: UserDayConstraint) async {
        let replanContext = buildContextualReplanContext(trigger: trigger, constraint: constraint)
        let title = trigger == .postWake ? "After Wake-Up" : "Around Your Outing"
        await planningVM.proposeContextualReplan(context: replanContext, title: title)
    }

    private func removeFromTimelineAndReplanSlot(taskId: String) async {
        let userId = firebase.resolvedUserId
        guard !userId.isEmpty,
              let task = shell.tasksVM.tasks.first(where: { $0.id == taskId && $0.status.isActive }),
              task.isSchedulerMovable,
              let slot = FreedSlotWindow.from(task: task) else {
            return
        }

        let removedTitle = task.title
        guard await shell.tasksVM.scheduleMutation.removeFromTimelineToday(taskID: taskId, userId: userId) != nil else {
            return
        }

        HapticManager.impact(.medium)
        await refreshTimelinePage(userId: userId)

        let replanContext = buildFreedSlotReplanContext(slot: slot, removedTitle: removedTitle)
        await planningVM.proposeContextualReplan(context: replanContext, title: "Fill This Slot")
    }

    private func buildFreedSlotReplanContext(
        slot: DayReplanAwayWindow,
        removedTitle: String
    ) -> DayReplanContext {
        DayReplanContext(
            planningContext: planningContext(),
            completedTasks: shell.tasksVM.completedToday,
            weatherSummary: weatherService.snapshot.chipSecondary,
            sleepHours: shell.brainVM.healthSummary?.totalSleepMinutes.map { $0 / 60.0 },
            userGoals: UserDefaults.standard.string(forKey: "userKeyGoals"),
            trigger: .freedSlot,
            freedSlotWindow: slot,
            removedTaskTitle: removedTitle
        )
    }

    private func buildContextualReplanContext(
        trigger: DayReplanTrigger,
        constraint: UserDayConstraint
    ) -> DayReplanContext {
        let now = Date()
        let calendar = Calendar.current
        let profile = UserLifeProfileStore.load()
        let wakeTime = constraint.wakeTime ?? now

        var awayWindow: DayReplanAwayWindow?
        if trigger == .goingOut,
           let departure = constraint.departureTime,
           let end = constraint.awayWindowEnd {
            awayWindow = DayReplanAwayWindow(start: departure, end: end)
        }

        let analysis = MissedTaskAnalyzer.analyze(
            MissedTaskAnalyzer.Input(
                tasks: shell.tasksVM.tasks,
                now: now,
                wakeTime: trigger == .postWake ? wakeTime : nil,
                expectedWakeHour: max(profile.workStartHour - 2, 6),
                awayWindow: awayWindow.map { MissedTaskAnalyzer.AwayWindow(start: $0.start, end: $0.end) },
                calendar: calendar
            )
        )

        return DayReplanContext(
            planningContext: planningContext(),
            completedTasks: shell.tasksVM.completedToday,
            weatherSummary: weatherService.snapshot.chipSecondary,
            sleepHours: shell.brainVM.healthSummary?.totalSleepMinutes.map { $0 / 60.0 },
            userGoals: UserDefaults.standard.string(forKey: "userKeyGoals"),
            trigger: trigger,
            activeConstraint: constraint,
            missedTasks: analysis.missed,
            awayWindow: awayWindow,
            minutesLate: analysis.minutesLate
        )
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

    private func submitPlanningTurnAndGetReply(text: String, startedWithVoice: Bool) async -> String {
        let userId = firebase.resolvedUserId
        let context = planningContext()
        let countBefore = planningVM.turns.count
        await planningVM.submit(
            text: text,
            startedWithVoice: startedWithVoice,
            context: context,
            tasksVM: shell.tasksVM,
            modulesVM: shell.modulesVM,
            userId: userId,
            refreshContext: planningRefreshContext(userId: userId)
        )
        if let last = planningVM.turns.last,
           planningVM.turns.count > countBefore,
           last.role == .assistant {
            return last.text
        }
        return "Done — I updated your plan."
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

    private func refreshTimelinePage(userId: String, lightweight: Bool = false) async {
        if lightweight {
            await refreshTimelineAfterPlanning(userId: userId)
            return
        }
        let name = UserLifeProfileStore.resolvedDisplayName()
        let peak = UserLifeProfileStore.load().peakStartHour
        await shell.refreshContext(
            userId: userId,
            userName: name,
            peakStartHour: peak
        )
    }

    private func refreshTimelineAfterPlanning(userId: String) async {
        await shell.syncScheduleAfterRescheduleApply(userId: userId)
        planningVM.refreshTimeline(from: shell.timelineService.snapshot.today)
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
        shell.syncBrainLiveProgress(userId: userId)
        shell.refreshWidgetData(rebuildTimeline: false)
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
        shell.syncBrainLiveProgress(userId: userId)
        shell.refreshWidgetData(rebuildTimeline: false)
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

    private func openTaskList(filter: TaskFilter = .all) {
        taskListInitialFilter = filter
        showTasks = true
    }

    private func startBrainHeroTask(_ task: LifeTask?, instant: Bool = false, durationMinutes: Int? = nil) {
        if let task {
            tabBeforeFocus = selectedTab
            if instant {
                shell.adhdVM.startFocusSession(task: task, durationMinutes: durationMinutes)
            } else {
                shell.adhdVM.startCountdown(for: task) {
                    shell.adhdVM.startFocusSession(task: task, durationMinutes: durationMinutes)
                }
            }
            return
        }
        openCapture(source: .brain, hints: CaptureContextHints(screen: "brain"))
    }

    private func openCapture(source: CaptureSource, hints: CaptureContextHints = CaptureContextHints()) {
        captureSource = source
        captureContextHints = hints
        showBrainCapture = true
    }

    private func handleCaptureRouted(_ result: CaptureRouteResult) {
        captureToastMessage = result.outcome.plainToastMessage
        captureUndoTaskId = result.createdTaskId
        captureUndoInboxId = result.inboxItemId
        let view = viewAction(for: result)
        captureViewAction = view?.action
        captureViewLabel = view?.label ?? "View"
        showCaptureToast = true
        shell.refreshWidgetData()
    }

    private func viewAction(for result: CaptureRouteResult) -> (label: String, action: () -> Void)? {
        switch result.outcome {
        case .taskCreated(let taskId, _), .scheduledEvent(let taskId, _, _):
            return ("View", {
                selectedTab = .today
                if let task = shell.tasksVM.tasks.first(where: { $0.id == taskId }) {
                    shell.tasksVM.selectedTask = task
                    openTaskList()
                }
            })
        case .needsReview, .queuedOffline:
            return ("Inbox", { showInbox = true })
        case .journalEntry, .insightSaved:
            return ("Journal", { selectedTab = .brain })
        case .healthLog:
            return ("Health", { showHealthDetail = true })
        case .archived:
            return nil
        }
    }

    private func undoLastCapture() {
        guard let taskId = captureUndoTaskId else { return }
        Task {
            await CaptureRouter.shared.undoTask(
                taskId: taskId,
                inboxItemId: captureUndoInboxId,
                userId: firebase.resolvedUserId,
                taskRepo: TaskRepository()
            )
            shell.refreshWidgetData()
        }
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
            await refreshTimelinePage(userId: userId, lightweight: true)
        }
    }

    private func triggerCalendarChangeReplan() async {
        guard shell.pendingCalendarChange != nil else { return }
        let replanContext = DayReplanContext(
            planningContext: planningContext(),
            completedTasks: shell.tasksVM.completedToday,
            weatherSummary: weatherService.snapshot.chipSecondary,
            sleepHours: shell.brainVM.healthSummary?.totalSleepMinutes.map { $0 / 60.0 },
            userGoals: UserDefaults.standard.string(forKey: "userKeyGoals"),
            trigger: .calendarChange
        )
        await planningVM.proposeContextualReplan(context: replanContext, title: "Calendar Change")
        shell.clearPendingCalendarChange()
    }

    private func bindPlanningSpeechHandler() {
        planningVM.onSpeakReply = { text in
            guard planningVM.inputMode == .voice else { return }
            guard SpeechVoiceSettings.autoSpeakReplies else { return }
            guard selectedTab != .brain else { return }
            planningSpeech.speak(text)
        }
    }

    private func handleProactiveNegotiation(_ option: String) async {
        let action = shell.proactiveActions.first {
            $0.surface == .banner || $0.surface == .autoApplyPreview
        }
        let env = ProactiveActionRouter.Environment(
            shell: shell,
            planningVM: planningVM,
            userId: firebase.resolvedUserId,
            planningContext: { planningContext() },
            refreshContext: planningRefreshContext(userId: firebase.resolvedUserId),
            startFocusSession: { task, minutes in
                tabBeforeFocus = selectedTab
                shell.adhdVM.startFocusSession(task: task, durationMinutes: minutes)
            },
            showModules: { showModules = true },
            triggerCalendarReplan: { await triggerCalendarChangeReplan() },
            applyRecoveryTemplate: { await applyRecoveryTemplate(from: $0) },
            submitPlanningNegotiation: { await submitPlanningNegotiation($0) },
            shareAccountabilityMessage: { message in
                accountabilityShareMessage = message
                showAccountabilityShare = true
            }
        )
        _ = await ProactiveActionRouter.handle(option: option, action: action, env: env)
    }

    private func applyRecoveryTemplate(from option: String) async {
        let template: RecoveryDayTemplate
        if option.lowercased().contains("recovery") {
            template = .recovery
        } else if option.lowercased().contains("gentle") {
            template = .gentlePush
        } else {
            template = .minimumViable
        }
        let context = DayReplanContext(
            planningContext: planningContext(),
            completedTasks: shell.tasksVM.completedToday,
            trigger: .badDay
        )
        let variant = RecoveryTemplateApplier.apply(
            template: template,
            tasks: shell.tasksVM.tasks,
            context: context
        )
        await planningVM.applySelectedVariant(
            variant,
            context: planningContext(),
            tasksVM: shell.tasksVM,
            modulesVM: shell.modulesVM,
            userId: firebase.resolvedUserId,
            refreshContext: planningRefreshContext(userId: firebase.resolvedUserId)
        )
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

    @ViewBuilder
    private var fullTimelineSheet: some View {
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
                            openTaskList()
                        }
                    },
                    onRescheduleTask: { taskId in
                        Task { await rescheduleTimelineTask(taskId: taskId) }
                    },
                    onRemoveFromTimelineTask: { taskId in
                        Task { await removeFromTimelineAndReplanSlot(taskId: taskId) }
                    },
                    onPersistScheduleChange: { task in
                        let userId = firebase.resolvedUserId
                        guard !userId.isEmpty else { return }
                        Task {
                            await shell.tasksVM.scheduleMutation.persist(
                                task,
                                userId: userId,
                                userPlaced: true
                            )
                        }
                    },
                    taskForID: resolveTimelineTask,
                    parentScrollDisabled: $fullTimelineScrollDisabled
                )
                .padding(.horizontal, DesignSystem.BriefingViewport.sectionHorizontal)
                .padding(.vertical, DesignSystem.spacingMD)
            }
            .scrollDisabled(fullTimelineScrollDisabled)
            .scrollViewScrollLock(fullTimelineScrollDisabled)
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
}

/// Isolates ADHD overlay observation so 1 Hz focus ticks don't redraw the whole root canvas (PERF-019).
private struct ADHDOverlayHost: View {
    @ObservedObject var adhdVM: ADHDViewModel
    let onDecideForMe: () -> Void
    let onVoiceCapture: () -> Void
    let onResetMode: () -> Void

    var body: some View {
        ZStack {
            if adhdVM.isEmergencyMode {
                EmergencyModeView(adhdVM: adhdVM) { task in
                    adhdVM.startCountdown(for: task) {
                        adhdVM.startFocusSession(task: task)
                    }
                }
                .transition(.opacity)
                .zIndex(100)
                VStack {
                    Spacer()
                    ADHDFloatingDockView(
                        onDecideForMe: onDecideForMe,
                        onVoiceCapture: onVoiceCapture,
                        onResetMode: onResetMode
                    )
                    .padding(.bottom, 12)
                }
            }

            if adhdVM.isFocusSessionActive {
                FocusSessionView(adhdVM: adhdVM)
                    .zIndex(99)
                    .ignoresSafeArea()
            }
        }
        .allowsHitTesting(adhdVM.isEmergencyMode || adhdVM.isFocusSessionActive)
    }
}
