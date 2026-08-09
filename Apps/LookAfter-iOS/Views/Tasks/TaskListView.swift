import SwiftUI
import LookAfterCore
import LookAfterAI
import LookAfterData
import LookAfterFeatures

/// Task List View — shows all tasks with filtering and management.
struct TaskListView: View {
    
    @ObservedObject var tasksVM: TasksViewModel
    let adhdVM: ADHDViewModel
    var brainVM: BrainViewModel?
    let userId: String
    let initialFilter: TaskFilter
    
    @State private var showCreateTask = false
    @State private var showImportTasks = false
    @State private var editingTask: LifeTask?
    @State private var fullEditTask: LifeTask?
    @State private var selectedFilter: TaskFilter
    @State private var selectedLifeArea: LifeArea?
    @State private var isCardStackMode = false
    @StateObject private var plannerVM = DailyPlannerViewModel()
    @State private var showReschedulePreview = false

    // Performance optimization: Cache filtered/sorted tasks to avoid recomputation on every render
    @State private var cachedFilteredTasks: [LifeTask] = []
    @State private var lastFilterApplied: TaskFilter
    @State private var lastTasksHash: Int = 0
    @State private var timeDisplayRefreshTask: Task<Void, Never>?

    init(
        tasksVM: TasksViewModel,
        adhdVM: ADHDViewModel,
        brainVM: BrainViewModel? = nil,
        userId: String,
        initialFilter: TaskFilter = .all
    ) {
        self.tasksVM = tasksVM
        self.adhdVM = adhdVM
        self.brainVM = brainVM
        self.userId = userId
        self.initialFilter = initialFilter
        _selectedFilter = State(initialValue: initialFilter)
        _lastFilterApplied = State(initialValue: initialFilter)
    }
    
    var body: some View {
        ZStack {
            PremiumBackground()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(isCardStackMode ? "Focus Stack" : listTitle)
                        .font(.dsLargeTitle())
                        .foregroundColor(DesignSystem.textPrimary)
                    
                    Spacer()
                    
                    Button(action: {
                        HapticManager.impact(.light)
                        withAnimation(.spring()) {
                            isCardStackMode.toggle()
                        }
                    }) {
                        Image(systemName: isCardStackMode ? "list.bullet" : "square.stack.3d.up.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(isCardStackMode ? DesignSystem.accentPrimary : DesignSystem.textMuted)
                            .padding(DesignSystem.spacingSM)
                            .background(Circle().fill(DesignSystem.backgroundElevated))
                    }
                    .minTouchTarget()
                    
                    Button(action: { showImportTasks = true }) {
                        Image(systemName: "square.and.arrow.down.on.square")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(DesignSystem.accentPrimary)
                            .padding(DesignSystem.spacingSM)
                            .background(Circle().fill(DesignSystem.backgroundElevated))
                    }
                    .minTouchTarget()
                    .accessibilityLabel("Import tasks from file")
                    
                    Button(action: { showCreateTask.toggle() }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                    .minTouchTarget()

                    Menu(content: {
                        Button(action: {
                            Task { await proposeReplan() }
                        }, label: {
                            Label("Adjust schedule", systemImage: "sparkles")
                        })
                        .disabled(plannerVM.isScheduling)
                        .accessibilityLabel("Adjust schedule")

                        Button(action: {
                            Task { await proposeTomorrowPlan() }
                        }, label: {
                            Label("Plan Tomorrow", systemImage: "sunrise")
                        })
                        .disabled(plannerVM.isScheduling)
                    }, label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 22))
                            .foregroundColor(DesignSystem.textSecondary)
                    })
                    .minTouchTarget()
                    .accessibilityLabel("Task actions")
                }
                .padding(DesignSystem.spacingLG)
                
                if isCardStackMode {
                    TaskCardStackView(
                        tasksVM: tasksVM,
                        adhdVM: adhdVM,
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
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    // Animate on revision, not a freshly allocated id array every body pass (PERF-012).
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: tasksVM.tasksContentRevision)
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
            TaskFormSheet(tasksVM: tasksVM, mode: .create)
        }
        .sheet(isPresented: $showImportTasks) {
            TaskImportSheet(tasksVM: tasksVM, userId: userId)
        }
        .sheet(item: $editingTask) { task in
            QuickTaskEditSheet(
                tasksVM: tasksVM,
                task: task,
                onMoreOptions: { fullEditTask = $0 }
            )
        }
        .sheet(item: $fullEditTask) { task in
            TaskFormSheet(tasksVM: tasksVM, mode: .edit(task))
        }
        .task {
            if tasksVM.tasks.isEmpty, tasksVM.completedToday.isEmpty {
                await tasksVM.loadTasks(userId: userId)
            }
            updateFilteredTasksIfNeeded()
            scheduleTimeDisplayRefresh()
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
                userId: userId
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
                Label("Plan", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold, design: .default))
            })
            .buttonStyle(.borderedProminent)
            .disabled(plannerVM.isScheduling)
        }
        .padding(.horizontal, DesignSystem.spacingLG)
        .padding(.bottom, 8)
    }
    
    /// Update cached filtered tasks only when filter or tasks change (performance optimization).
    private func updateFilteredTasksIfNeeded() {
        let currentHash = tasksVM.tasksContentRevision
            &+ tasksVM.tasks
                .map { "\($0.id):\($0.status.rawValue):\($0.title):\($0.updatedAt.timeIntervalSince1970)" }
                .joined()
                .hashValue
            &+ tasksVM.recurrenceTemplates
                .map { "\($0.id):\($0.title):\($0.updatedAt.timeIntervalSince1970)" }
                .joined()
                .hashValue
            &+ tasksVM.completedToday.map(\.id).joined().hashValue
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
        switch selectedFilter {
        case .all:
            return TaskListSorter.sortByPriorityThenSchedule(
                TaskScheduleQuery.uniqueActiveTasks(
                    from: tasksVM.tasks,
                    context: context,
                    calendar: calendar
                )
            )
        case .today:
            return TaskListSorter.sortForToday(
                tasksVM.tasks.filter { $0.isActionableToday(allTasks: context, calendar: calendar) }
            )
        case .tomorrow:
            return TaskListSorter.sortByPriorityThenSchedule(
                tasksVM.tasks.filter { $0.isActionableTomorrow(allTasks: context, calendar: calendar) }
            )
        case .upcoming:
            return TaskListSorter.sortByPriorityThenSchedule(
                tasksVM.tasks.filter { $0.isUpcoming(allTasks: context, calendar: calendar) }
            )
        case .active:
            return TaskListSorter.sortByPriorityThenSchedule(
                tasksVM.tasks.filter { $0.isActiveBacklog(calendar: calendar) }
            )
        case .scheduled:
            return TaskListSorter.sortByPriorityThenSchedule(
                tasksVM.tasks.filter { $0.isScheduledTask(allTasks: tasksVM.schedulingContext, calendar: calendar) }
            )
        case .completed:
            return tasksVM.completedToday
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
    
    @State private var title = ""
    @State private var description = ""
    @State private var lifeArea: LifeArea = .personal
    @State private var priority: Priority = .medium
    @State private var difficulty: TaskDifficulty = .medium
    @State private var estimatedMinutes = 30
    @State private var estimatedMinutesText = "30"
    @State private var recurrence: TaskRecurrence = .none
    @State private var selectedWeekdays: Set<Int> = []
    @State private var schedulingMode: TaskSchedulingMode = .flexible
    @State private var fixedStartTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var fixedEndTime = Calendar.current.date(bySettingHour: 17, minute: 30, second: 0, of: Date()) ?? Date()
    @State private var autoFillError: String?
    @State private var isSaving = false
    @State private var showAdvancedOptions = false
    
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

                            if recurrence == .custom {
                                WeekdaySelectionView(selectedWeekdays: $selectedWeekdays)
                            }
                        }
                    }

                    Section("Scheduling") {
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
                    }
                    
                    Section("Time Estimate") {
                        HStack(spacing: 12) {
                            TextField("Minutes", text: $estimatedMinutesText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 72)
                                .onSubmit(commitEstimatedMinutesText)

                            Text("minutes")
                                .font(.system(size: 15, design: .default))
                                .foregroundColor(DesignSystem.textMuted)

                            Spacer(minLength: 0)

                            Stepper("", value: $estimatedMinutes, in: 1...240)
                                .labelsHidden()
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
            .onChange(of: estimatedMinutes) { _, newValue in
                estimatedMinutesText = String(newValue)
            }
            .keyboardDismissToolbar(label: "Done")
        }
    }
    
    private func loadExistingValues() {
        if case .edit(let task) = mode {
            title = task.title
            description = task.description
            lifeArea = task.lifeArea
            priority = task.priority
            difficulty = task.difficulty
            estimatedMinutes = task.estimatedMinutes
            estimatedMinutesText = String(task.estimatedMinutes)
            let recurrenceFields = tasksVM.recurrenceFieldsForEditing(task)
            recurrence = recurrenceFields.recurrence
            selectedWeekdays = Set(recurrenceFields.weekdays)
            schedulingMode = task.timeConstraintValue.asSchedulingMode
            if let start = task.scheduledTime { fixedStartTime = start }
            if let end = task.scheduledEndTime { fixedEndTime = end }
            return
        }

        let profile = UserLifeProfileStore.load()
        let calendar = Calendar.current
        let today = Date()
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
        estimatedMinutes = min(value, 240)
        estimatedMinutesText = String(estimatedMinutes)
    }
    
    private func fillWithAI() {
        autoFillError = nil
        HapticManager.impact(.light)
        Task {
            guard let result = await tasksVM.autoFillDetails(for: title) else {
                autoFillError = "AI couldn't fill details. Activate your product key in Settings → License."
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
        let startTime = schedulingMode == .fixedTime ? fixedStartTime : nil
        let endTime = schedulingMode == .fixedTime ? fixedEndTime : nil

        switch self.mode {
        case .create:
            let task = LifeTask(
                title: title,
                description: description,
                lifeArea: lifeArea,
                priority: priority,
                difficulty: difficulty,
                estimatedMinutes: estimatedMinutes,
                requiredEnergy: difficulty.minimumEnergy,
                scheduledTime: startTime,
                recurrence: recurrence == .none ? nil : recurrence,
                recurrenceWeekdays: weekdays,
                schedulingMode: scheduling,
                scheduledEndTime: endTime
            )
            HapticManager.impact(.medium)
            tasksVM.createTask(task)
        case .edit(let existing):
            var updated = existing
            updated.title = title
            updated.description = description
            updated.lifeArea = lifeArea
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
            updated.updatedAt = Date()
            HapticManager.impact(.medium)
            isSaving = true
            Task {
                let userId = updated.userId.isEmpty ? existing.userId : updated.userId
                await tasksVM.scheduleMutation.persist(
                    updated,
                    userId: userId,
                    userPlaced: scheduling == .fixedTime
                )
                isSaving = false
                if tasksVM.error == nil {
                    HapticManager.notification(.success)
                    dismiss()
                }
            }
            return
        }
        HapticManager.notification(.success)
        dismiss()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repeat on")
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundColor(DesignSystem.textMuted)

            HStack(spacing: 8) {
                ForEach(WeekdaySelection.allSymbols, id: \.weekday) { entry in
                    let isSelected = selectedWeekdays.contains(entry.weekday)
                    Button(action: {
                        if isSelected {
                            selectedWeekdays.remove(entry.weekday)
                        } else {
                            selectedWeekdays.insert(entry.weekday)
                        }
                    }, label: {
                        Text(String(entry.label.prefix(1)))
                            .font(.system(size: 13, weight: .bold, design: .default))
                            .frame(width: 34, height: 34)
                            .background(
                                Circle().fill(isSelected ? DesignSystem.accentPrimary.opacity(0.35) : Color.white.opacity(0.08))
                            )
                            .foregroundColor(isSelected ? DesignSystem.textPrimary : DesignSystem.textMuted)
                    })
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
