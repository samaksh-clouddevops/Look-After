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
    
    @State private var showCreateTask = false
    @State private var showImportTasks = false
    @State private var editingTask: LifeTask?
    @State private var selectedFilter: TaskFilter = .today
    @State private var selectedLifeArea: LifeArea?
    @State private var isCardStackMode = false
    @StateObject private var plannerVM = DailyPlannerViewModel()
    @State private var showReschedulePreview = false
    @State private var showWhatIfSheet = false
    @State private var simulationResult: SimulationResult?

    // Performance optimization: Cache filtered/sorted tasks to avoid recomputation on every render
    @State private var cachedFilteredTasks: [LifeTask] = []
    @State private var lastFilterApplied: TaskFilter = .today
    @State private var lastTasksHash: Int = 0
    
    var body: some View {
        ZStack {
            PremiumBackground()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(isCardStackMode ? "Focus Stack" : "Tasks")
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

                        Button(action: {
                            HapticManager.impact(.light)
                            showWhatIfSheet = true
                        }, label: {
                            Label("What-If…", systemImage: "wand.and.stars")
                        })
                        .accessibilityLabel("Simulate what-if schedule")
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
                                tasksVM: tasksVM,
                                adhdVM: adhdVM,
                                editingTask: $editingTask,
                                onComplete: handleComplete,
                                onDelete: handleDelete
                            )
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: cachedFilteredTasks.map(\.id))
                    .onAppear { updateFilteredTasksIfNeeded() }
                    .onChange(of: selectedFilter) { _, _ in updateFilteredTasksIfNeeded() }
                    .onChange(of: tasksVM.tasks.count) { _, _ in updateFilteredTasksIfNeeded() }
                    .onChange(of: tasksVM.completedToday.count) { _, _ in updateFilteredTasksIfNeeded() }
                    // Cheap invalidation signal when tasks mutate without count change (complete/status).
                    .onChange(of: tasksVM.tasks.first?.updatedAt) { _, _ in updateFilteredTasksIfNeeded() }
                    .onChange(of: tasksVM.tasks.last?.updatedAt) { _, _ in updateFilteredTasksIfNeeded() }
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
            TaskFormSheet(tasksVM: tasksVM, mode: .edit(task))
        }
        .sheet(isPresented: $showWhatIfSheet) {
            TaskFormSheet(tasksVM: tasksVM, mode: .hypothetical) { task in
                let result = tasksVM.simulateSchedule(hypotheticalTask: task)
                // Defer so the form sheet can finish dismissing first.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    simulationResult = result
                }
            }
        }
        .fullScreenCover(item: $simulationResult) { result in
            SimulationTimelineView(
                result: result,
                onDiscard: {
                    simulationResult = nil
                },
                onCommit: { intent in
                    tasksVM.commitSimulation(intent)
                    simulationResult = nil
                }
            )
        }
        .task {
            await tasksVM.loadTasks(userId: userId)
            updateFilteredTasksIfNeeded()
        }
        .task(id: cachedFilteredTasks.map(\.id).joined()) {
            await refreshTaskTimeDisplays()
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
        // Include status + updatedAt so mutations (complete/reschedule) invalidate the cache.
        let currentHash = tasksVM.tasks
            .map { "\($0.id):\($0.status.rawValue):\($0.updatedAt.timeIntervalSince1970)" }
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
    case today, tomorrow, upcoming, active, scheduled, completed

    var displayName: String {
        switch self {
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
        /// Builds a task without persisting — used by What-If simulation.
        case hypothetical

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let task): return task.id
            case .hypothetical: return "hypothetical"
            }
        }

        var isEditing: Bool {
            if case .edit = self { return true }
            return false
        }

        var isHypothetical: Bool {
            if case .hypothetical = self { return true }
            return false
        }
    }

    @ObservedObject var tasksVM: TasksViewModel
    let mode: Mode
    /// When set (hypothetical mode), called with the drafted task instead of persisting.
    var onHypotheticalSave: ((LifeTask) -> Void)?

    init(
        tasksVM: TasksViewModel,
        mode: Mode,
        onHypotheticalSave: ((LifeTask) -> Void)? = nil
    ) {
        self.tasksVM = tasksVM
        self.mode = mode
        self.onHypotheticalSave = onHypotheticalSave
    }

    @State private var title = ""
    @State private var description = ""
    @State private var lifeArea: LifeArea = .personal
    @State private var priority: Priority = .medium
    @State private var difficulty: TaskDifficulty = .medium
    @State private var estimatedMinutes = 30
    @State private var recurrence: TaskRecurrence = .none
    @State private var selectedWeekdays: Set<Int> = []
    @State private var schedulingMode: TaskSchedulingMode = .flexible
    @State private var fixedStartTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var fixedEndTime = Calendar.current.date(bySettingHour: 17, minute: 30, second: 0, of: Date()) ?? Date()
    @State private var autoFillError: String?

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
                    
                    Section("Categorize") {
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
                        Stepper("\(estimatedMinutes) minutes", value: $estimatedMinutes, in: 1...240, step: 1)
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
            .navigationTitle(navigationTitleText)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(tasksVM.isAutoFilling)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmationTitle, action: saveTask)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || tasksVM.isAutoFilling)
                }
            }
            .onAppear(perform: loadExistingValues)
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
            let recurrenceFields = tasksVM.recurrenceFieldsForEditing(task)
            recurrence = recurrenceFields.recurrence
            selectedWeekdays = Set(recurrenceFields.weekdays)
            schedulingMode = task.schedulingModeValue
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
    }
    
    private func fillWithAI() {
        autoFillError = nil
        HapticManager.impact(.light)
        Task {
            guard let result = await tasksVM.autoFillDetails(for: title) else {
                autoFillError = "AI couldn't fill details. Add a GLM key in Settings → API Keys."
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
    
    private var navigationTitleText: String {
        if mode.isHypothetical { return "What-If Task" }
        return mode.isEditing ? "Edit Task" : "New Task"
    }

    private var confirmationTitle: String {
        if mode.isHypothetical { return "Simulate" }
        return mode.isEditing ? "Save" : "Create"
    }

    private func saveTask() {
        KeyboardDismiss.dismiss()
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
            let task = makeDraftTask(
                scheduling: scheduling,
                startTime: startTime,
                endTime: endTime,
                weekdays: weekdays
            )
            HapticManager.impact(.medium)
            tasksVM.createTask(task)
        case .hypothetical:
            let task = makeDraftTask(
                scheduling: scheduling,
                startTime: startTime,
                endTime: endTime,
                weekdays: weekdays
            )
            HapticManager.impact(.medium)
            onHypotheticalSave?(task)
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
            updated.schedulingMode = scheduling
            updated.scheduledTime = startTime
            updated.scheduledEndTime = endTime
            updated.updatedAt = Date()
            HapticManager.impact(.medium)
            tasksVM.updateTask(updated)
        }
        HapticManager.notification(.success)
        dismiss()
    }

    private func makeDraftTask(
        scheduling: TaskSchedulingMode,
        startTime: Date?,
        endTime: Date?,
        weekdays: [Int]?
    ) -> LifeTask {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        // Flexible what-if tasks still need a proposed window so cascade can rank/shift them.
        let resolvedStart: Date? = {
            if let startTime { return startTime }
            if mode.isHypothetical {
                return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: dayStart)
            }
            return nil
        }()
        let resolvedEnd: Date? = {
            if let endTime { return endTime }
            guard let resolvedStart else { return nil }
            return resolvedStart.addingTimeInterval(TimeInterval(max(estimatedMinutes, 1) * 60))
        }()

        var task = LifeTask(
            title: title,
            description: description,
            lifeArea: lifeArea,
            priority: priority,
            difficulty: difficulty,
            estimatedMinutes: estimatedMinutes,
            requiredEnergy: difficulty.minimumEnergy,
            scheduledDate: dayStart,
            scheduledTime: resolvedStart,
            recurrence: recurrence == .none ? nil : recurrence,
            recurrenceWeekdays: weekdays,
            schedulingMode: scheduling,
            scheduledEndTime: resolvedEnd
        )
        // Fluid when flexible so cascade can absorb/reposition during dry-run.
        if scheduling != .fixedTime {
            task.timeConstraint = .fluid
        } else {
            task.timeConstraint = .anchored
        }
        return task
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
