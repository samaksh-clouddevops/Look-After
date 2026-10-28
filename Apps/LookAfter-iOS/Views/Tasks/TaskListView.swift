import SwiftUI
import LookAfterCore
import LookAfterAI
import LookAfterData
import LookAfterFeatures

/// Task List View — shows all tasks with filtering and management.
struct TaskListView: View {
    
    @ObservedObject var tasksVM: TasksViewModel
    @ObservedObject var adhdVM: ADHDViewModel
    var brainVM: BrainViewModel?
    let userId: String
    let initialFilter: TaskFilter
    let initialTask: LifeTask?
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showCreateTask = false
    @State private var showImportTasks = false
    @State private var editingTask: LifeTask?
    @State private var fullEditTask: LifeTask?
    @State private var pendingFullEditTask: LifeTask?
    @State private var lastOpenedTaskID: String?
    @State private var selectedFilter: TaskFilter
    @State private var selectedLifeArea: LifeArea?
    @State private var isCardStackMode = false
    @StateObject private var plannerVM = DailyPlannerViewModel()
    @State private var showReschedulePreview = false
    @Namespace private var taskZoomNamespace

    // Performance optimization: Cache filtered/sorted tasks to avoid recomputation on every render
    @State private var cachedFilteredTasks: [LifeTask] = []
    @State private var lastFilterApplied: TaskFilter
    @State private var lastTasksHash: Int = 0
    @State private var timeDisplayRefreshTask: Task<Void, Never>?

    private var taskZoomEnabled: Bool { !reduceMotion }

    init(
        tasksVM: TasksViewModel,
        adhdVM: ADHDViewModel,
        brainVM: BrainViewModel? = nil,
        userId: String,
        initialFilter: TaskFilter = .all,
        initialTask: LifeTask? = nil
    ) {
        self.tasksVM = tasksVM
        self.adhdVM = adhdVM
        self.brainVM = brainVM
        self.userId = userId
        self.initialFilter = initialFilter
        self.initialTask = initialTask
        _selectedFilter = State(initialValue: initialFilter)
        _lastFilterApplied = State(initialValue: initialFilter)
    }
    
    var body: some View {
        ZStack {
            PremiumBackground()
            
            VStack(spacing: 0) {
                taskListHeader
                    .padding(.horizontal, DesignSystem.screenHorizontal)
                    .padding(.vertical, DesignSystem.spacingSM)

                if isCardStackMode {
                    TaskCardStackView(
                        tasksVM: tasksVM,
                        adhdVM: adhdVM,
                        taskZoomNamespace: taskZoomNamespace,
                        zoomEnabled: taskZoomEnabled,
                        onTaskDeferred: { task in
                            guard FlowDirectorFeature.isEnabled, let brainVM else { return }
                            Task { await brainVM.handleTaskDeferred(task, userId: userId) }
                        }
                    )
                } else {
                    FilterChipBar(items: TaskFilter.allCases, selection: $selectedFilter) { $0.displayName }
                        .padding(.bottom, 4)

                    if selectedFilter == .tomorrow {
                        tomorrowPlanningBanner
                    }

                    List {
                        if !tasksVM.completedToday.isEmpty && selectedFilter != .completed {
                            Section {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(DesignSystem.success)
                                    Text("\(tasksVM.completedToday.count) completed today")
                                        .font(.system(size: 13, weight: .semibold, design: .default))
                                        .foregroundColor(DesignSystem.success)
                                    Spacer()
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                        
                        ForEach(cachedFilteredTasks) { task in
                            TaskListRowView(
                                task: task,
                                isDecomposing: tasksVM.isDecomposing(taskId: task.id),
                                timeDisplayLabel: tasksVM.timeDisplay(for: task).lineLabel,
                                isLoadingTimeDisplay: tasksVM.isLoadingTimeDisplay(taskId: task.id),
                                taskZoomNamespace: taskZoomNamespace,
                                zoomEnabled: taskZoomEnabled,
                                editingTask: $editingTask,
                                onComplete: handleComplete,
                                onDelete: handleDelete,
                                onMarkIncomplete: { Task { await tasksVM.markIncomplete(task) } },
                                onStart: {
                                    adhdVM.startCountdown(for: task) {
                                        adhdVM.startFocusSession(task: task)
                                    }
                                },
                                onDecompose: { Task { await tasksVM.decomposeTask(task) } },
                                onDuplicate: { tasksVM.duplicateTask(task) }
                            )
                        }
                    }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #else
                    .listStyle(.inset)
                    #endif
                    .scrollContentBackground(.hidden)
                    .overlay {
                        if cachedFilteredTasks.isEmpty, !tasksVM.isLoading {
                            ContentUnavailableView {
                                Label("No tasks here", systemImage: "checklist")
                            } description: {
                                Text(selectedFilter == .all
                                     ? "Add something you want to make time for."
                                     : "There are no tasks in \(selectedFilter.displayName.lowercased()).")
                            } actions: {
                                Button("Add task", systemImage: "plus") { showCreateTask = true }
                                    .buttonStyle(.glassProminent)
                                    .tint(LookAfterChrome.accentTint)
                            }
                        }
                    }
                    .scrollEdgeEffectStyle(.soft, for: .bottom)
                    // Animate on revision, not a freshly allocated id array every body pass (PERF-012).
                    .animation(PremiumMotion.spring(reduceMotion: reduceMotion), value: tasksVM.tasksContentRevision)
                    .onAppear { updateFilteredTasksIfNeeded() }
                    .onChange(of: selectedFilter) { _, _ in
                        updateFilteredTasksIfNeeded()
                        scheduleTimeDisplayRefresh()
                    }
                    .onChange(of: tasksVM.tasksContentRevision) { _, _ in
                        updateFilteredTasksIfNeeded()
                        scheduleTimeDisplayRefresh()
                    }
                    .onChange(of: editingTask?.id) { _, _ in updateFilteredTasksIfNeeded() }
                }
            }
        }
        .sheet(isPresented: $showCreateTask) {
            TaskFormSheet(tasksVM: tasksVM, mode: .create, userId: userId, initialDate: newTaskDate)
        }
        .sheet(isPresented: $showImportTasks) {
            TaskImportSheet(tasksVM: tasksVM, userId: userId)
        }
        .sheet(item: $editingTask, onDismiss: {
            if let draft = pendingFullEditTask {
                pendingFullEditTask = nil
                fullEditTask = draft
            }
        }) { task in
            QuickTaskEditSheet(
                tasksVM: tasksVM,
                task: task,
                onMoreOptions: { pendingFullEditTask = $0 }
            )
            .lookAfterZoomDestination(
                sourceID: task.id,
                in: taskZoomNamespace,
                enabled: taskZoomEnabled
            )
        }
        .sheet(item: $fullEditTask) { task in
            TaskFormSheet(tasksVM: tasksVM, mode: .edit(task), userId: userId)
                .lookAfterZoomDestination(
                    sourceID: task.id,
                    in: taskZoomNamespace,
                    enabled: taskZoomEnabled
                )
        }
        .task {
            if tasksVM.tasks.isEmpty, tasksVM.completedToday.isEmpty {
                await tasksVM.loadTasks(userId: userId)
            }
            updateFilteredTasksIfNeeded()
            scheduleTimeDisplayRefresh()
            openRequestedTask()
        }
        .onChange(of: initialTask?.id) { _, _ in
            openRequestedTask()
        }
        .onChange(of: adhdVM.isCountdownActive) { _, active in
            if active { dismiss() }
        }
        .onDisappear {
            timeDisplayRefreshTask?.cancel()
        }
        .undoToast(
            isShowing: Binding(
                get: { tasksVM.isUndoToastVisible },
                set: { if !$0 { tasksVM.clearPendingUndo() } }
            ),
            message: tasksVM.undoToastMessage,
            onUndo: { Task { await tasksVM.performUndo() } },
            onDismiss: { tasksVM.clearPendingUndo() }
        )
        .sheet(isPresented: $showReschedulePreview) {
            reschedulePreviewContent
        }
        .onChange(of: plannerVM.rescheduleProposal?.id) { _, newID in
            showReschedulePreview = newID != nil
        }
        .accessibilityIdentifier("screen-task-list")
    }

    private var taskListHeader: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
                    taskListTitle
                    HStack {
                        Spacer(minLength: 0)
                        taskListActions
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: LAChromeMetrics.toolbarGap) {
                        taskListTitle
                        taskListActions
                    }
                    VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
                        taskListTitle
                        HStack {
                            Spacer(minLength: 0)
                            taskListActions
                        }
                    }
                }
            }
        }
    }

    private var taskListTitle: some View {
        HStack(spacing: DesignSystem.spacingSM) {
            LAToolbarIconButton(
                systemName: "xmark",
                accessibilityLabel: "Close",
                action: { dismiss() }
            )
            Text(isCardStackMode ? "Focus Stack" : listTitle)
                .font(.dsTitle())
                .foregroundStyle(DesignSystem.textPrimary)
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
    }

    private var taskListActions: some View {
        HStack(spacing: LAChromeMetrics.toolbarGap) {
            LAToolbarIconButton(
                systemName: "plus",
                prominence: .primary,
                accessibilityLabel: "Add task",
                action: { showCreateTask = true }
            )
            .accessibilityIdentifier("task-list-add")
            Menu(content: {
                Button(action: { showImportTasks = true }, label: {
                    Label("Import tasks", systemImage: "square.and.arrow.down.on.square")
                })

                Button(action: {
                    HapticManager.impact(.light)
                    withAnimation(PremiumMotion.spring(reduceMotion: reduceMotion)) {
                        isCardStackMode.toggle()
                    }
                }, label: {
                    Label(
                        isCardStackMode ? "Show list" : "Show focus stack",
                        systemImage: isCardStackMode ? "list.bullet" : "square.stack.3d.up.fill"
                    )
                })

                Divider()

                Button(action: {
                    Task { await proposeReplan() }
                }, label: {
                    Label("Adjust schedule", systemImage: "sparkles")
                })
                .disabled(plannerVM.isScheduling)

                Button(action: {
                    Task { await proposeTomorrowPlan() }
                }, label: {
                    Label("Plan tomorrow", systemImage: "sunrise")
                })
                .disabled(plannerVM.isScheduling)
            }, label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: LAChromeMetrics.iconPointSize, weight: LAChromeMetrics.iconWeight))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(DesignSystem.textPrimary)
                    .frame(width: DesignSystem.iconButtonSize, height: DesignSystem.iconButtonSize)
                    .contentShape(Rectangle())
            })
            .buttonStyle(.glass)
            .tint(DesignSystem.textSecondary)
            .accessibilityLabel("More task actions")
        }
    }

    private var newTaskDate: Date {
        selectedFilter == .tomorrow
            ? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            : Date()
    }

    private func openRequestedTask() {
        guard let task = initialTask, task.id != lastOpenedTaskID else { return }
        lastOpenedTaskID = task.id
        editingTask = task
    }

    private var listTitle: String {
        switch selectedFilter {
        case .all: return "All Tasks"
        default: return "Tasks"
        }
    }

    @ViewBuilder
    private var reschedulePreviewContent: some View {
        if let proposal = plannerVM.rescheduleProposal {
            ReschedulePreviewSheet(
                plannerVM: plannerVM,
                proposal: proposal,
                userId: userId,
                tasksViewModel: tasksVM
            )
        }
    }

    private func proposeReplan() async {
        await plannerVM.loadToday(userId: userId)
        let healthContext = BackgroundAnalyticsService.shared.cachedAIContext(userId: userId)?.promptBlock
        await plannerVM.proposeDayReschedule(userId: userId, healthContext: healthContext)
    }

    private func proposeTomorrowPlan() async {
        selectedFilter = .tomorrow
        await plannerVM.loadTomorrow(userId: userId)
        let healthContext = BackgroundAnalyticsService.shared.cachedAIContext(userId: userId)?.promptBlock
        await plannerVM.proposeTomorrowReschedule(userId: userId, healthContext: healthContext)
    }

    private func handleDelete(_ task: LifeTask) {
        HapticManager.notification(.warning)
        Task { _ = await tasksVM.deleteTask(task) }
    }

    private func handleComplete(_ task: LifeTask) {
        HapticManager.notification(.success)
        Task { await tasksVM.completeTask(task) }
    }

    private func scheduleTimeDisplayRefresh() {
        timeDisplayRefreshTask?.cancel()
        timeDisplayRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await refreshTaskTimeDisplays()
        }
    }

    private func refreshTaskTimeDisplays() async {
        let snapshot = brainVM?.cognitiveSnapshot
        let sleepQuality: SleepQuality? = {
            guard let snapshot else { return nil }
            if snapshot.sleepDebtHours > 2 { return .poor }
            if snapshot.recoveryScore < 0.45 { return .fair }
            return nil
        }()
        let context = TaskFocusStretchResolver.Context.fromProfile(
            energyScore: snapshot?.energyScore,
            sleepQuality: sleepQuality,
            executiveCapacity: nil
        )
        await tasksVM.refreshTimeDisplays(for: cachedFilteredTasks, context: context)
    }

    private var tomorrowPlanningBanner: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tomorrow")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundColor(DesignSystem.textPrimary)
                Text("Preview what's coming and let AI slot flexible tasks.")
                    .font(.system(size: 12, design: .default))
                    .foregroundColor(DesignSystem.textMuted)
            }
            Spacer()
            Button(action: {
                Task { await proposeTomorrowPlan() }
            }, label: {
                Group {
                    if plannerVM.isScheduling {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Planning…")
                        }
                    } else {
                        Label("Plan", systemImage: "sparkles")
                    }
                }
                .font(.system(size: 13, weight: .semibold, design: .default))
                .padding(.horizontal, DesignSystem.spacingSM)
                .padding(.vertical, 8)
            })
            .buttonStyle(.glassProminent)
            .tint(LookAfterChrome.accentTint)
            .disabled(plannerVM.isScheduling)
            .animation(.easeInOut(duration: 0.2), value: plannerVM.isScheduling)
        }
        .padding(.horizontal, DesignSystem.spacingLG)
        .padding(.bottom, 8)
    }
    
    /// Update cached filtered tasks only when filter or tasks change (performance optimization).
    private func updateFilteredTasksIfNeeded() {
        let currentHash = tasksVM.tasksContentRevision
            &+ tasksVM.listPool
                .map { "\($0.id):\($0.status.rawValue):\($0.title):\($0.updatedAt.timeIntervalSince1970)" }
                .joined()
                .hashValue
            &+ tasksVM.recurrenceTemplates
                .map { "\($0.id):\($0.title):\($0.updatedAt.timeIntervalSince1970)" }
                .joined()
                .hashValue
            &+ tasksVM.completedToday.map(\.id).joined().hashValue
            &+ tasksVM.inactiveTasks.map(\.id).joined().hashValue
        if selectedFilter != lastFilterApplied || currentHash != lastTasksHash {
            cachedFilteredTasks = computeFilteredTasks()
            lastFilterApplied = selectedFilter
            lastTasksHash = currentHash
        }
    }

    /// Compute filtered tasks (called only when necessary, not on every render).
    private func computeFilteredTasks() -> [LifeTask] {
        let calendar = Calendar.current
        let context = tasksVM.schedulingContext
        let pool = tasksVM.listPool
        switch selectedFilter {
        case .all:
            // Full plate — today-sliced `tasksVM.tasks` hid multi-day slices and future routines.
            let allActive = tasksVM.localAllTasks(userId: userId).filter {
                $0.status.isActive && !TaskRecurrenceEngine.isRecurrenceTemplate($0)
            }
            let plateContext = tasksVM.localAllTasks(userId: userId)
            return TaskListSorter.sortForToday(
                TaskScheduleQuery.uniqueActiveTasks(
                    from: allActive,
                    context: plateContext,
                    calendar: calendar
                )
            )
        case .today:
            return TaskListSorter.sortForToday(
                tasksVM.tasks.filter { $0.isActionableToday(allTasks: context, calendar: calendar) }
            )
        case .tomorrow:
            return TaskListSorter.sortByPriorityThenSchedule(
                pool.filter { $0.isActionableTomorrow(allTasks: context, calendar: calendar) }
            )
        case .upcoming:
            let plate = tasksVM.localAllTasks(userId: userId)
            return TaskListSorter.sortByPriorityThenSchedule(
                plate.filter {
                    $0.status.isActive
                        && !TaskRecurrenceEngine.isRecurrenceTemplate($0)
                        && $0.isUpcoming(allTasks: plate, calendar: calendar)
                }
            )
        case .active:
            let plate = tasksVM.localAllTasks(userId: userId)
            return TaskListSorter.sortForToday(
                plate.filter {
                    $0.status.isActive
                        && !TaskRecurrenceEngine.isRecurrenceTemplate($0)
                        && $0.isActiveTask(allTasks: plate, calendar: calendar)
                }
            )
        case .scheduled:
            let plate = tasksVM.localAllTasks(userId: userId)
            return TaskListSorter.sortByPriorityThenSchedule(
                plate.filter {
                    $0.status.isActive
                        && !TaskRecurrenceEngine.isRecurrenceTemplate($0)
                        && $0.isScheduledThisWeek(calendar: calendar)
                }
            )
        case .completed:
            let calendar = Calendar.current
            let cutoff = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: Date())) ?? Date()
            return tasksVM.inactiveTasks.filter {
                $0.isInactiveWithNoFutureOccurrence(allTasks: context, calendar: calendar)
                    && $0.inactivityMoment >= cutoff
            }
        }
    }
}

enum TaskFilter: String, CaseIterable {
    case all, today, tomorrow, upcoming, active, scheduled, completed

    var displayName: String {
        switch self {
        case .all: return "All"
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .upcoming: return "Upcoming"
        case .active: return "Active"
        case .scheduled: return "Scheduled"
        case .completed: return "Completed"
        }
    }
}

/// Unified create/edit task sheet with AI auto-fill.
struct TaskFormSheet: View {
    enum Mode: Identifiable {
        case create
        case edit(LifeTask)
        
        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let task): return task.id
            }
        }
        
        var isEditing: Bool {
            if case .edit = self { return true }
            return false
        }
    }
    
    @ObservedObject var tasksVM: TasksViewModel
    let mode: Mode
    var userId: String = ""
    var initialDate: Date = Date()
    
    @State private var title = ""
    @State private var description = ""
    @State private var lifeArea: LifeArea = .personal
    @State private var workCategory: WorkTaskCategory = .task
    @State private var priority: Priority = .medium
    @State private var difficulty: TaskDifficulty = .medium
    @State private var estimatedMinutes = 30
    @State private var estimatedMinutesText = "30"
    @State private var recurrence: TaskRecurrence = .none
    @State private var selectedWeekdays: Set<Int> = []
    @State private var schedulingMode: TaskSchedulingMode = .flexible
    @State private var fixedStartTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var fixedEndTime = Calendar.current.date(bySettingHour: 17, minute: 30, second: 0, of: Date()) ?? Date()
    @State private var placeJustForToday = false
    @State private var todayOnlyTime = Date()
    @State private var autoFillError: String?
    @State private var isSaving = false
    @State private var showAdvancedOptions = false
    @State private var isMultiDay = false
    @State private var multiDayCount = 3
    @State private var taskDate = Date()
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                PremiumBackground()
                
                PremiumForm {
                    Section {
                        TextField("What needs to be done?", text: $title)
                            .font(.system(.body, design: .default))
                        
                        if title.trimmingCharacters(in: .whitespaces).count >= 3 {
                            Button(action: fillWithAI) {
                                HStack(spacing: 8) {
                                    if tasksVM.isAutoFilling {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("AI is filling details...")
                                    } else {
                                        Image(systemName: "sparkles")
                                        Text(mode.isEditing ? "Fill with AI" : "Fill details with AI")
                                    }
                                }
                                .font(.system(size: 14, weight: .semibold, design: .default))
                                .foregroundColor(DesignSystem.textMuted)
                            }
                            .disabled(tasksVM.isAutoFilling)
                        }
                        
                        if let err = autoFillError {
                            Text(err)
                                .font(.system(size: 12, design: .default))
                                .foregroundColor(DesignSystem.error)
                        }
                        
                        TextField("Details (optional)", text: $description, axis: .vertical)
                            .font(.system(.body, design: .default))
                            .lineLimit(3...6)
                    }
                    
                    Section("Categorize & repeat") {
                        DisclosureGroup("Advanced options", isExpanded: $showAdvancedOptions) {
                            Picker("Life Area", selection: $lifeArea) {
                                ForEach(LifeArea.allCases) { area in
                                    Label(area.rawValue, systemImage: area.icon)
                                        .tag(area)
                                }
                            }

                            if lifeArea == .work {
                                Picker("Work Type", selection: $workCategory) {
                                    ForEach(WorkTaskCategory.allCases) { category in
                                        Label(category.rawValue, systemImage: category.icon)
                                            .tag(category)
                                    }
                                }
                            }

                            Picker("Priority", selection: $priority) {
                                ForEach(Priority.allCases) { p in
                                    Text(p.label).tag(p)
                                }
                            }

                            Picker("Difficulty", selection: $difficulty) {
                                ForEach(TaskDifficulty.allCases) { d in
                                    Text(d.rawValue).tag(d)
                                }
                            }

                            Picker("Repeat", selection: $recurrence) {
                                ForEach(TaskRecurrence.allCases) { r in
                                    Text(r.rawValue).tag(r)
                                }
                            }

                            if showsWeekdayPicker {
                                WeekdaySelectionView(selectedWeekdays: $selectedWeekdays) {
                                    if recurrence == .weekdays || recurrence == .weekends {
                                        recurrence = .custom
                                    }
                                }
                            }
                        }
                    }

                    Section("Scheduling") {
                        if recurrence == .none {
                            DatePicker(isMultiDay ? "Starting day" : "Day", selection: $taskDate, displayedComponents: .date)
                                .accessibilityIdentifier("task-form-day")
                        }
                        Picker("Type", selection: $schedulingMode) {
                            ForEach(TaskSchedulingMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }

                        Text(schedulingMode.subtitle)
                            .font(.system(size: 12, design: .default))
                            .foregroundColor(DesignSystem.textMuted)

                        if schedulingMode == .fixedTime {
                            DatePicker("Start", selection: $fixedStartTime, displayedComponents: .hourAndMinute)
                            DatePicker("End", selection: $fixedEndTime, displayedComponents: .hourAndMinute)
                        }

                        Toggle(recurrence != .none ? "Time just for today" : "Choose a time for this day", isOn: $placeJustForToday)
                        if placeJustForToday {
                            DatePicker(recurrence != .none ? "Today" : "Time", selection: $todayOnlyTime, displayedComponents: .hourAndMinute)
                            Text(recurrence != .none
                                 ? "Uses this time today. A repeat keeps its usual time on other days."
                                 : "Places this task at the chosen time on the selected day.")
                                .font(.dsCaption())
                                .foregroundStyle(DesignSystem.textMuted)
                        }
                    }
                    
                    Section("Time Estimate") {
                        if !mode.isEditing {
                            Toggle("Split across multiple days", isOn: $isMultiDay)
                        }

                        if isMultiDay && !mode.isEditing {
                            Stepper("Over \(multiDayCount) days", value: $multiDayCount, in: 2...90)
                            Text("Creates one task per day (~\((estimatedMinutes / max(multiDayCount, 1)).durationString)/day) linked under this goal.")
                                .font(.system(size: 12, design: .default))
                                .foregroundColor(DesignSystem.textMuted)
                        }

                        HStack(spacing: 12) {
                            TextField(isMultiDay ? "Total minutes" : "Minutes", text: $estimatedMinutesText)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 72)
                                .onSubmit(commitEstimatedMinutesText)

                            Text("minutes")
                                .font(.system(size: 15, design: .default))
                                .foregroundColor(DesignSystem.textMuted)

                            Spacer(minLength: 0)

                            Stepper("", value: $estimatedMinutes, in: 1...(isMultiDay ? 6000 : 1440))
                                .labelsHidden()
                        }

                        if !isMultiDay, !mode.isEditing,
                           let suggestion = MultiDaySuggestion.suggest(forRawMinutes: estimatedMinutes) {
                            Button {
                                isMultiDay = true
                                multiDayCount = suggestion.dayCount
                            } label: {
                                Label(
                                    "This looks like \(suggestion.dayCount) days of work \u{2014} tap to split into multi-day tasks",
                                    systemImage: "calendar.badge.clock"
                                )
                                .font(.system(size: 12, weight: .medium, design: .default))
                            }
                            .foregroundColor(DesignSystem.warning)
                        }

                        if let warning = DaySupervisorContinuity.createDurationWarning(
                            estimatedMinutes: estimatedMinutes,
                            remainingFlexMinutes: tasksVM.dayRemainingFlexMinutes()
                        ), !mode.isEditing, !isMultiDay, Calendar.current.isDateInToday(taskDate) {
                            Text(warning)
                                .font(.system(size: 12, design: .default))
                                .foregroundColor(DesignSystem.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    
                    if mode.isEditing {
                        Section {
                            Button(role: .destructive, action: deleteTask) {
                                HStack {
                                    Spacer()
                                    Label("Delete Task", systemImage: "trash")
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .disabled(tasksVM.isAutoFilling)
            }
            .navigationTitle(mode.isEditing ? "Edit Task" : "New Task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(tasksVM.isAutoFilling)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.isEditing ? "Save" : "Create", action: saveTask)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || tasksVM.isAutoFilling || isSaving)
                }
            }
            .onAppear(perform: loadExistingValues)
            .onChange(of: recurrence) { _, newValue in
                applyWeekdayPreset(for: newValue)
            }
            .onChange(of: estimatedMinutes) { _, newValue in
                estimatedMinutesText = String(newValue)
            }
            .keyboardDismissToolbar(label: "Done")
        }
    }
    
    private func loadExistingValues() {
        if case .edit(let task) = mode {
            taskDate = Calendar.current.startOfDay(for: task.scheduledDate ?? task.scheduledTime ?? Date())
            title = task.title
            description = task.description
            lifeArea = task.lifeArea
            workCategory = task.workCategory ?? .task
            priority = task.priority
            difficulty = task.difficulty
            estimatedMinutes = task.estimatedMinutes
            estimatedMinutesText = String(task.estimatedMinutes)
            let recurrenceFields = tasksVM.recurrenceFieldsForEditing(task)
            recurrence = recurrenceFields.recurrence
            selectedWeekdays = Set(recurrenceFields.weekdays)
            applyWeekdayPreset(for: recurrenceFields.recurrence)
            schedulingMode = task.timeConstraintValue.asSchedulingMode
            if let start = task.scheduledTime {
                fixedStartTime = start
                todayOnlyTime = start
            }
            if let end = task.scheduledEndTime { fixedEndTime = end }
            return
        }

        let profile = UserLifeProfileStore.load()
        let calendar = Calendar.current
        taskDate = calendar.startOfDay(for: initialDate)
        let today = taskDate
        fixedStartTime = calendar.date(bySettingHour: profile.workStartHour, minute: profile.workStartMinute, second: 0, of: today) ?? today
        fixedEndTime = calendar.date(bySettingHour: profile.workEndHour, minute: profile.workEndMinute, second: 0, of: today) ?? today
        estimatedMinutes = TaskDurationPolicy.defaultMinutes
        estimatedMinutesText = String(estimatedMinutes)
    }

    private func commitEstimatedMinutesText() {
        let digits = estimatedMinutesText.filter(\.isNumber)
        guard let value = Int(digits), value >= 1 else {
            estimatedMinutesText = String(estimatedMinutes)
            return
        }
        estimatedMinutes = min(value, isMultiDay ? 6000 : 1440)
        estimatedMinutesText = String(estimatedMinutes)
    }
    
    private func fillWithAI() {
        autoFillError = nil
        HapticManager.impact(.light)
        Task {
            guard let result = await tasksVM.autoFillDetails(for: title) else {
                autoFillError = tasksVM.autoFillError ?? "Couldn’t suggest details. Try again, or fill them in yourself."
                return
            }
            description = result.description
            lifeArea = result.lifeArea
            priority = result.priority
            difficulty = result.difficulty
            estimatedMinutes = result.estimatedMinutes
            recurrence = result.recurrence
            HapticManager.notification(.success)
        }
    }
    
    private func saveTask() {
        KeyboardDismiss.dismiss()
        commitEstimatedMinutesText()
        guard recurrence != .custom || !selectedWeekdays.isEmpty else {
            autoFillError = "Select at least one day for custom recurrence."
            return
        }
        guard schedulingMode != .fixedTime || fixedEndTime > fixedStartTime else {
            autoFillError = "End time must be after start time for fixed events."
            return
        }

        let weekdays = recurrence == .custom ? Array(selectedWeekdays).sorted() : nil
        let scheduling = schedulingMode == .fixedTime ? TaskSchedulingMode.fixedTime : TaskSchedulingMode.flexible
        let creationDay = Calendar.current.startOfDay(for: taskDate)
        let startTime = schedulingMode == .fixedTime
            ? (recurrence == .none ? TodayOnlySchedule.clock(on: creationDay, from: fixedStartTime) : fixedStartTime)
            : nil
        let endTime = schedulingMode == .fixedTime
            ? (recurrence == .none ? TodayOnlySchedule.clock(on: creationDay, from: fixedEndTime) : fixedEndTime)
            : nil

        switch self.mode {
        case .create:
            if isMultiDay {
                let dayCount = max(multiDayCount, 1)
                let baseMinutes = max(TaskDurationPolicy.minimumMinutes, estimatedMinutes / dayCount)
                var remainder = max(0, estimatedMinutes - (baseMinutes * dayCount))
                let draft = MultiDayPlanDraft(
                    title: title,
                    dayCount: dayCount,
                    lifeArea: lifeArea,
                    slices: (0..<dayCount).map { index in
                        let extra = remainder > 0 ? 1 : 0
                        if remainder > 0 { remainder -= 1 }
                        return MultiDaySliceDraft(
                            dayIndex: index,
                            title: "Day \(index + 1): \(title)",
                            estimatedMinutes: baseMinutes + extra,
                            windowLabel: ""
                        )
                    }
                )
                var plan = MultiDayTaskPlanner.plan(
                    from: draft,
                    userId: userId,
                    existingTasks: tasksVM.tasks,
                    startDate: creationDay
                )
                plan.parent.description = description
                plan.parent.priority = priority
                plan.parent.difficulty = difficulty
                plan.parent.requiredEnergy = difficulty.minimumEnergy
                for index in plan.slices.indices {
                    plan.slices[index].priority = priority
                    plan.slices[index].difficulty = difficulty
                    plan.slices[index].requiredEnergy = difficulty.minimumEnergy
                    if !description.isEmpty {
                        plan.slices[index].description = description
                    }
                }
                HapticManager.impact(.medium)
                isSaving = true
                Task {
                    do {
                        try await tasksVM.createMultiDayTasksAndAwait(plan: plan)
                        isSaving = false
                        HapticManager.notification(.success)
                        dismiss()
                    } catch {
                        isSaving = false
                        autoFillError = error.localizedDescription
                        HapticManager.notification(.error)
                    }
                }
                return
            }
            var task = LifeTask(
                title: title,
                description: description,
                lifeArea: lifeArea,
                priority: priority,
                difficulty: difficulty,
                estimatedMinutes: TaskDurationPolicy.clamp(estimatedMinutes),
                requiredEnergy: difficulty.minimumEnergy,
                scheduledDate: recurrence == .none ? creationDay : nil,
                scheduledTime: startTime,
                recurrence: recurrence == .none ? nil : recurrence,
                recurrenceWeekdays: weekdays,
                schedulingMode: scheduling,
                scheduledEndTime: endTime,
                userId: userId,
                workCategory: lifeArea == .work ? workCategory : nil
            )
            if placeJustForToday, recurrence == .none,
               let clock = TodayOnlySchedule.clock(on: creationDay, from: todayOnlyTime) {
                TodayOnlySchedule.apply(&task, start: clock, on: creationDay)
            }
            HapticManager.impact(.medium)
            isSaving = true
            Task {
                do {
                    try await tasksVM.createTaskAndAwait(task)
                    isSaving = false
                    HapticManager.notification(.success)
                    dismiss()
                } catch {
                    isSaving = false
                    autoFillError = error.localizedDescription
                    HapticManager.notification(.error)
                }
            }
            return
        case .edit(let existing):
            var updated = existing
            updated.title = title
            updated.description = description
            updated.lifeArea = lifeArea
            updated.workCategory = lifeArea == .work ? workCategory : nil
            updated.priority = priority
            updated.difficulty = difficulty
            updated.estimatedMinutes = estimatedMinutes
            updated.requiredEnergy = difficulty.minimumEnergy
            updated.recurrence = recurrence == .none ? nil : recurrence
            updated.recurrenceWeekdays = weekdays
            updated.applyUserSchedulingModeEdit(
                scheduling,
                fixedStartTime: startTime,
                fixedEndTime: endTime
            )
            if recurrence == .none {
                updated.scheduledDate = creationDay
                if placeJustForToday,
                   let clock = TodayOnlySchedule.clock(on: creationDay, from: todayOnlyTime) {
                    TodayOnlySchedule.apply(&updated, start: clock, on: creationDay)
                } else if scheduling == .flexible, let oldClock = updated.scheduledTime {
                    updated.scheduledTime = TodayOnlySchedule.clock(on: creationDay, from: oldClock)
                    updated.scheduledEndTime = updated.scheduledTime?.addingTimeInterval(TimeInterval(estimatedMinutes * 60))
                }
            } else if placeJustForToday {
                updated.scheduledDate = existing.scheduledDate
                updated.scheduledTime = existing.scheduledTime
                updated.scheduledEndTime = existing.scheduledEndTime
                updated.timeConstraint = existing.timeConstraint
                updated.schedulingMode = existing.schedulingMode
                updated.userPlacedScheduleAt = existing.userPlacedScheduleAt
            }
            updated.updatedAt = Date()
            HapticManager.impact(.medium)
            isSaving = true
            Task {
                let userId = updated.userId.isEmpty ? existing.userId : updated.userId
                var succeeded = await tasksVM.scheduleMutation.persist(
                    updated,
                    userId: userId,
                    userPlaced: scheduling == .fixedTime && !placeJustForToday
                )
                if succeeded, placeJustForToday, recurrence != .none {
                    succeeded = await tasksVM.rescheduleJustForToday(updated, to: todayOnlyTime) != nil
                }
                isSaving = false
                if succeeded {
                    HapticManager.notification(.success)
                    dismiss()
                } else {
                    autoFillError = tasksVM.error ?? "Couldn’t save your changes. Please try again."
                    HapticManager.notification(.error)
                }
            }
            return
        }
    }
    
    private var showsWeekdayPicker: Bool {
        switch recurrence {
        case .custom, .weekdays, .weekends:
            return true
        default:
            return false
        }
    }

    /// Weekdays and weekends fill the day buttons. Custom with nothing picked starts on Monday.
    private func applyWeekdayPreset(for rule: TaskRecurrence) {
        switch rule {
        case .weekdays:
            selectedWeekdays = [2, 3, 4, 5, 6]
        case .weekends:
            selectedWeekdays = [1, 7]
        case .custom where selectedWeekdays.isEmpty:
            selectedWeekdays = [2]
        default:
            break
        }
    }

    private func deleteTask() {
        guard case .edit(let task) = mode else { return }
        HapticManager.notification(.warning)
        Task {
            _ = await tasksVM.deleteTask(task)
            dismiss()
        }
    }
}

struct WeekdaySelectionView: View {
    @Binding var selectedWeekdays: Set<Int>
    var onUserToggle: () -> Void = {}

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repeat on")
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundColor(DesignSystem.textMuted)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(WeekdaySelection.allSymbols, id: \.weekday) { entry in
                    let isSelected = selectedWeekdays.contains(entry.weekday)
                    Button(action: {
                        if isSelected {
                            selectedWeekdays.remove(entry.weekday)
                        } else {
                            selectedWeekdays.insert(entry.weekday)
                        }
                        onUserToggle()
                    }, label: {
                        Text(entry.label)
                            .font(.system(size: 13, weight: .bold, design: .default))
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(
                                Capsule().fill(
                                    isSelected
                                        ? DesignSystem.accentPrimary
                                        : DesignSystem.contentSurfaceSubtle
                                )
                            )
                            .foregroundColor(isSelected ? DesignSystem.accentOnPrimary : DesignSystem.textMuted)
                    })
                    .buttonStyle(.plain)
                    .accessibilityLabel(entry.label)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
