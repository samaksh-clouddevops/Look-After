import Foundation
import LookAfterCore
import LookAfterAI
import LookAfterData

/// ViewModel for the Task list and task management.
@MainActor
public final class TasksViewModel: ObservableObject {
    
    @Published public var tasks: [LifeTask] = []
    @Published public var completedToday: [LifeTask] = []
    @Published public private(set) var recurrenceTemplates: [LifeTask] = []
    @Published public var isLoading: Bool = false
    @Published public var error: String?
    @Published public var selectedTask: LifeTask?
    @Published public var isDecomposing: Bool = false
    @Published public private(set) var decomposingTaskId: String?
    @Published public private(set) var taskTimeDisplays: [String: TaskTimeDisplayInfo] = [:]
    @Published public private(set) var loadingTimeDisplayTaskIds: Set<String> = []
    @Published public var isAutoFilling: Bool = false
    @Published public var isImporting: Bool = false
    @Published public var importPreview: TaskImportResult?
    @Published public var importError: String?
    @Published public var pendingUndo: TaskUndoAction?
    @Published public private(set) var isUndoToastVisible = false
    @Published public private(set) var undoToastMessage = ""
    
    private let taskRepo: TaskStoring
    private let taskStore: TaskStore?
    private let decomposer: TaskDecomposer
    private let autoFiller: TaskAutoFiller
    private let taskImporter: TaskImporter
    private let semanticAnalyzer: TaskSemanticAnalyzer
    private let focusStretchRefiner = TaskFocusStretchRefiner()
    private var undoDismissTask: Task<Void, Never>?
    private var loadGeneration = 0
    
    /// Active, completed-today, and recurrence templates for schedule validation.
    public var schedulingContext: [LifeTask] {
        taskStore?.snapshot.schedulingContext ?? (tasks + completedToday + recurrenceTemplates)
    }

    /// Active task occurrences — excludes recurrence templates.
    public var activeTasks: [LifeTask] {
        tasks.filter { $0.status.isActive && !$0.isRecurrenceTemplateTask }
    }

    /// Full on-device task history for analytics and gap detection.
    public func localAllTasks(userId: String) -> [LifeTask] {
        taskRepo.localAllTasks(for: userId)
    }
    
    public init(
        taskStore: TaskStore = .shared,
        decomposer: TaskDecomposer,
        autoFiller: TaskAutoFiller? = nil
    ) {
        self.taskStore = taskStore
        self.taskRepo = taskStore
        self.decomposer = decomposer
        self.autoFiller = autoFiller ?? TaskAutoFiller()
        self.taskImporter = TaskImporter()
        self.semanticAnalyzer = TaskSemanticAnalyzer()
    }

    init(taskRepo: TaskStoring, decomposer: TaskDecomposer, autoFiller: TaskAutoFiller, taskImporter: TaskImporter, semanticAnalyzer: TaskSemanticAnalyzer? = nil) {
        self.taskStore = taskRepo as? TaskStore
        self.taskRepo = taskRepo
        self.decomposer = decomposer
        self.autoFiller = autoFiller
        self.taskImporter = taskImporter
        self.semanticAnalyzer = semanticAnalyzer ?? TaskSemanticAnalyzer()
    }
    
    /// Load tasks — warms on-device cache off-main, paints local snapshot, then syncs remote.
    public func loadTasks(userId: String) async {
        let generation = loadGeneration + 1
        loadGeneration = generation

        // Cold launch: decode tasks.json on the I/O queue before first snapshot read.
        await taskRepo.warmLocalCache(for: userId)
        guard generation == loadGeneration else { return }

        applySnapshot(taskRepo.localSnapshot(for: userId), logSource: "launch-cache")

        let showSpinner = tasks.isEmpty && completedToday.isEmpty
        if showSpinner { isLoading = true }

        do {
            _ = try await taskRepo.getTaskLists(for: userId)
            guard generation == loadGeneration else { return }
            try await syncRecurringOccurrences(userId: userId)
            guard generation == loadGeneration else { return }
            applySnapshot(taskRepo.localSnapshot(for: userId), logSource: "remote-sync")
            await backfillMissingSemanticProfiles(userId: userId)
            await reconcileTodaySchedule(userId: userId)
        } catch {
            guard generation == loadGeneration else { return }
            self.error = error.localizedDescription
        }

        if generation == loadGeneration {
            isLoading = false
        }
    }

    /// Reload from on-device cache only — fast path after local mutations.
    public func refreshFromLocal(userId: String) {
        if let taskStore {
            taskStore.refreshLocal(userId: userId)
            applySnapshot(taskStore.snapshot, logSource: "local-refresh")
        } else {
            applySnapshot(taskRepo.localSnapshot(for: userId), logSource: "local-refresh")
        }
    }

    private func notifyTaskListDidChange() {
        guard taskStore == nil else { return }
        NotificationCenter.default.post(name: .taskListDidChange, object: nil)
    }

    private func applySnapshot(_ snapshot: TaskListSnapshot, logSource: String) {
        tasks = snapshot.active
        completedToday = snapshot.completedToday
        recurrenceTemplates = snapshot.templates
        print("[Tasks] VM apply snapshot source=\(logSource) active=\(snapshot.active.count) completedToday=\(snapshot.completedToday.count) templates=\(snapshot.templates.count)")
    }

    /// Normalize legacy recurring tasks, remove invalid day instances, and materialize today's occurrences.
    public func syncRecurringSchedule(userId: String) async {
        guard !userId.isEmpty else { return }
        do {
            try await syncRecurringOccurrences(userId: userId)
            applySnapshot(taskRepo.localSnapshot(for: userId), logSource: "recurrence-sync")
        } catch {
            print("[Tasks] recurrence sync failed: \(error.localizedDescription)")
        }
    }

    /// Normalize legacy recurring tasks and materialize today's occurrences.
    private func syncRecurringOccurrences(userId: String) async throws {
        var all = try await taskRepo.getAll(for: userId)

        for task in all where TaskRecurrenceEngine.needsLegacyNormalization(task) {
            let matchingTemplate = all.first {
                TaskRecurrenceEngine.isRecurrenceTemplate($0)
                    && $0.title.caseInsensitiveCompare(task.title) == .orderedSame
                    && $0.id != task.id
            }
            if matchingTemplate != nil {
                try await taskRepo.delete(task.id)
                print("[Tasks] removed duplicate legacy recurring id=\(task.id.prefix(8)) title=\"\(task.title)\"")
                continue
            }

            let alreadyLinked = all.contains { $0.parentTaskId == task.id }
            guard !alreadyLinked else { continue }

            let (template, occurrence) = TaskRecurrenceEngine.normalizeLegacyRecurringTask(task)
            try await taskRepo.create(template)
            try await taskRepo.update(occurrence)
            print("[Tasks] normalized legacy recurring template=\(template.id.prefix(8))")
        }

        all = try await taskRepo.getAll(for: userId)
        let invalidIDs = TaskRecurrenceEngine.invalidScheduledTaskIDs(in: all)
        try await supersedeInvalidScheduledTasks(invalidIDs, in: all)
        if !invalidIDs.isEmpty {
            all = all.filter { !invalidIDs.contains($0.id) }
        }

        for task in all where TaskRecurrenceEngine.isRecurrenceTemplate(task) {
            guard task.semanticProfile == nil
                || task.expirationPolicy == nil
                || task.collisionStrategy == nil
                || task.temporalBoundingBox == nil else { continue }
            try await taskRepo.update(TaskEphemeralityDefaults.enrich(task))
        }
        all = try await taskRepo.getAll(for: userId)

        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)
        let materializeDays = [today] + (tomorrow.map { [$0] } ?? [])
        try await reactivateSupersededOccurrences(userId: userId, days: materializeDays, in: all)
        all = try await taskRepo.getAll(for: userId)

        let missing = TaskRecurrenceEngine.missingOccurrences(for: all, on: Date())
            .filter { !$0.isLifeCommitmentTask }
        for var occurrence in missing {
            occurrence.userId = userId
            try await taskRepo.create(occurrence)
            print("[Tasks] scheduler created occurrence template=\(occurrence.parentTaskId?.prefix(8) ?? "?")")
        }

        if let tomorrow {
            all = try await taskRepo.getAll(for: userId)
            let tomorrowMissing = TaskRecurrenceEngine.missingOccurrences(for: all, on: tomorrow)
                .filter { !$0.isLifeCommitmentTask }
            for var occurrence in tomorrowMissing {
                occurrence.userId = userId
                try await taskRepo.create(occurrence)
                print("[Tasks] scheduler created tomorrow occurrence template=\(occurrence.parentTaskId?.prefix(8) ?? "?")")
            }
        }

        // Re-run after materialization in case stale rows were merged back in.
        all = try await taskRepo.getAll(for: userId)
        let remainingInvalid = TaskRecurrenceEngine.invalidScheduledTaskIDs(in: all)
        try await supersedeInvalidScheduledTasks(remainingInvalid, in: all)

        all = try await taskRepo.getAll(for: userId)
        let staleDuplicates = TaskScheduleQuery.supersededDuplicateIDs(in: all)
        try await supersedeInvalidScheduledTasks(staleDuplicates, in: all)

        if let model = LifeModelStore.load(), model.hasContent {
            await dedupeLifeCommitmentTasks(userId: userId, model: model)
        }
    }

    /// Reuse midnight-superseded rows instead of creating duplicate occurrences every refresh.
    private func reactivateSupersededOccurrences(
        userId: String,
        days: [Date],
        in allTasks: [LifeTask]
    ) async throws {
        let calendar = Calendar.current
        let templates = allTasks.filter(TaskRecurrenceEngine.isRecurrenceTemplate)
        guard !templates.isEmpty else { return }

        for day in days {
            let dayStart = calendar.startOfDay(for: day)
            for template in templates {
                guard template.recurrenceOccurs(on: dayStart, calendar: calendar) else { continue }
                guard !TaskRecurrenceEngine.hasActionableOccurrence(
                    for: template,
                    on: dayStart,
                    in: allTasks,
                    calendar: calendar
                ) else { continue }

                guard var stale = allTasks.first(where: { task in
                    task.parentTaskId == template.id
                        && task.status == .superseded
                        && task.scheduledDate.map { calendar.isDate($0, inSameDayAs: dayStart) } == true
                }) else { continue }

                stale.status = .pending
                stale.updatedAt = Date()
                try await taskRepo.update(stale)
                print("[Tasks] reactivated superseded occurrence id=\(stale.id.prefix(8)) template=\(template.id.prefix(8))")
            }
        }
    }

    /// Marks invalid recurrence rows as superseded instead of deleting user data.
    private func supersedeInvalidScheduledTasks(_ ids: [String], in allTasks: [LifeTask]) async throws {
        for id in ids {
            guard var task = allTasks.first(where: { $0.id == id }) else { continue }
            guard task.status.isActive else { continue }
            if task.isLifeCommitmentTask { continue }
            task.status = .superseded
            task.updatedAt = Date()
            try await taskRepo.update(task)
            tasks.removeAll { $0.id == id }
            completedToday.removeAll { $0.id == id }
            print("[Tasks] superseded invalid scheduled task id=\(id.prefix(8))")
        }
    }
    
    /// Persist onboarding starter tasks and refresh the task list.
    public func importOnboardingTasks(_ seedTasks: [LifeTask], userId: String) async {
        guard !userId.isEmpty, !seedTasks.isEmpty else { return }

        await removeOnboardingSeededTasks(userId: userId)

        for var task in seedTasks {
            task.userId = userId
            if task.recurrenceRule != .none {
                await persistRecurringTask(task, decompose: false)
            } else {
                tasks.insert(task, at: 0)
                do {
                    try await taskRepo.create(task)
                } catch {
                    tasks.removeAll { $0.id == task.id }
                    self.error = error.localizedDescription
                }
            }
        }

        do {
            try await syncRecurringOccurrences(userId: userId)
        } catch {
            print("[Tasks] onboarding recurrence sync failed: \(error.localizedDescription)")
        }

        applySnapshot(taskRepo.localSnapshot(for: userId), logSource: "onboarding-seed")
        notifyTaskListDidChange()
    }

    public func hasOnboardingTaggedTasks(userId: String) -> Bool {
        let snapshot = taskRepo.localSnapshot(for: userId)
        return (snapshot.active + snapshot.completedToday).contains { $0.tags.contains("onboarding") }
    }

    public func onboardingTasksNeedCleanup(userId: String) async -> Bool {
        guard let all = try? await taskRepo.getAll(for: userId) else { return false }
        return all.contains { task in
            OnboardingTaskSeeder.isJunkOnboardingTask(
                title: task.title,
                description: task.description
            ) || (task.tags.contains("onboarding") && task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    public func removeOnboardingSeededTasks(userId: String) async {
        guard let all = try? await taskRepo.getAll(for: userId) else { return }
        let junkIDs = Set(all.filter { task in
            task.tags.contains("onboarding")
                || OnboardingTaskSeeder.isJunkOnboardingTask(title: task.title, description: task.description)
        }.map(\.id))

        guard !junkIDs.isEmpty else { return }

        for id in junkIDs {
            try? await taskRepo.delete(id)
        }
        tasks.removeAll { junkIDs.contains($0.id) }
        completedToday.removeAll { junkIDs.contains($0.id) }
        applySnapshot(taskRepo.localSnapshot(for: userId), logSource: "onboarding-cleanup")
        notifyTaskListDidChange()
    }

    private func persistRecurringTask(_ task: LifeTask, decompose: Bool) async {
        var template = TaskEphemeralityDefaults.enrich(task)
        template.isRecurrenceTemplate = true
        template.scheduledDate = nil
        template.status = .pending
        template.completedAt = nil

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: task.scheduledDate ?? Date())
        let shouldCreateToday = template.recurrenceRule == .none
            || template.recurrenceOccurs(on: day, calendar: calendar)
        let occurrence = shouldCreateToday
            ? TaskRecurrenceEngine.makeOccurrence(from: task, template: template, scheduledDate: day)
            : nil

        if let occurrence {
            tasks.insert(occurrence, at: 0)
        }

        do {
            try await taskRepo.create(template)
            if let occurrence {
                try await taskRepo.create(occurrence)
                if decompose, occurrence.steps.isEmpty {
                    await decomposeTask(occurrence)
                }
            }
        } catch {
            if let occurrence {
                tasks.removeAll { $0.id == occurrence.id }
            }
            self.error = error.localizedDescription
        }
    }

    /// Create a new task — instant UI update, persistence runs in background.
    public func createTask(_ task: LifeTask) {
        if task.recurrenceRule != .none {
            createRecurringTask(task)
            return
        }
        if MultiDayTaskTags.isMultiDay(task) {
            insertTaskWithoutDecompose(task)
            return
        }

        tasks.insert(task, at: 0)
        
        Task {
            do {
                var enriched = task
                enriched.semanticProfile = await resolveSemanticProfile(for: task)
                if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[index] = enriched
                }
                try await taskRepo.create(enriched)
                
                if enriched.steps.isEmpty {
                    await decomposeTask(enriched)
                }
            } catch {
                tasks.removeAll { $0.id == task.id }
                self.error = error.localizedDescription
            }
        }
    }

    /// Creates a multi-day parent + slice tasks without running TaskDecomposer.
    public func createMultiDayTasks(plan: MultiDayTaskPlan) {
        insertTaskWithoutDecompose(plan.parent)
        for slice in plan.slices {
            insertTaskWithoutDecompose(slice)
        }
        if let project = plan.project {
            persistCreativeProject(project)
        }
        notifyTaskListDidChange()
    }

    /// Banner data for an active multi-day goal on a given day.
    public static func activeMultiDayBanner(
        from tasks: [LifeTask],
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> MultiDayBannerData? {
        let dayStart = calendar.startOfDay(for: date)
        let roots = tasks.filter { MultiDayTaskTags.isRoot($0) && $0.status.isActive }
        for root in roots {
            let slices = tasks.filter { $0.parentTaskId == root.id && MultiDayTaskTags.isSlice($0) }
                .sorted { ($0.scheduledDate ?? .distantFuture) < ($1.scheduledDate ?? .distantFuture) }
            guard !slices.isEmpty else { continue }
            let dayCount = root.deadline.flatMap { deadline in
                calendar.dateComponents([.day], from: dayStart, to: calendar.startOfDay(for: deadline)).day
            }.map { max($0 + 1, slices.count) } ?? slices.count

            if let todaySlice = slices.first(where: { task in
                guard let scheduled = task.scheduledDate else { return false }
                return calendar.isDate(scheduled, inSameDayAs: dayStart)
            }) {
                let index = slices.firstIndex(where: { $0.id == todaySlice.id }) ?? 0
                return MultiDayBannerData(
                    title: root.title,
                    dayIndex: index + 1,
                    dayCount: max(dayCount, slices.count),
                    sliceTitle: todaySlice.title
                )
            }
        }
        return nil
    }

    private func insertTaskWithoutDecompose(_ task: LifeTask) {
        tasks.insert(task, at: 0)
        Task {
            do {
                var enriched = task
                enriched.semanticProfile = await resolveSemanticProfile(for: task)
                if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[index] = enriched
                }
                try await taskRepo.create(enriched)
            } catch {
                tasks.removeAll { $0.id == task.id }
                self.error = error.localizedDescription
            }
        }
    }

    private func persistCreativeProject(_ project: CreativeProject) {
        let key = "lifeos_creative_projects"
        var projects: [CreativeProject] = []
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([CreativeProject].self, from: data) {
            projects = saved
        }
        projects.removeAll { $0.parentTaskId == project.parentTaskId }
        projects.append(project)
        if let data = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func createRecurringTask(_ task: LifeTask) {
        Task {
            await persistRecurringTask(task, decompose: true)
        }
    }
    
    /// Create a task from AI-processed inbox capture.
    public func createFromInbox(_ draft: InboxTaskDraft, userId: String) async throws {
        var task = LifeTask(
            title: draft.title,
            lifeArea: draft.lifeArea ?? .personal,
            priority: draft.priority ?? .medium,
            difficulty: draft.difficulty ?? .medium,
            estimatedMinutes: draft.estimatedMinutes,
            userId: userId
        )
        task.semanticProfile = await resolveSemanticProfile(for: task)
        try await taskRepo.create(task)
        tasks.insert(task, at: 0)
        notifyTaskListDidChange()
    }

    /// Update an existing task — instant UI, background persistence.
    public func updateTask(_ task: LifeTask) {
        let previous = tasks.first(where: { $0.id == task.id })
            ?? completedToday.first(where: { $0.id == task.id })
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        }
        if let index = completedToday.firstIndex(where: { $0.id == task.id }) {
            completedToday[index] = task
        }
        Task {
            do {
                var enriched = task
                if let previous, task.semanticFieldsChanged(comparedTo: previous) || task.semanticProfile == nil {
                    enriched.semanticProfile = await resolveSemanticProfile(for: task)
                    if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                        tasks[index] = enriched
                    }
                }
                try await taskRepo.update(enriched)
                try await syncRecurrenceEditsToTemplate(enriched)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// Finds the next open slot from now and moves an incomplete task there.
    public func rescheduleTaskFromNow(_ task: LifeTask) async -> Date? {
        guard task.status.isActive else { return nil }

        let calendar = Calendar.current
        let now = Date()
        let workHours = PlanningSchedulePolicy.WorkHours.from(profile: UserLifeProfileStore.load())
        let occupied = schedulingContext.filter { candidate in
            guard candidate.id != task.id, candidate.status.isActive else { return false }
            guard candidate.scheduledTime != nil else { return false }
            if let scheduledDate = candidate.scheduledDate {
                return calendar.isDate(scheduledDate, inSameDayAs: now)
            }
            return true
        }

        let allocations = DaySlotAllocator.allocate(
            requests: [
                DaySlotAllocator.Request(
                    id: task.id,
                    estimatedMinutes: max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes),
                    priority: task.priority
                )
            ],
            existingTasks: occupied,
            workHours: workHours,
            now: now,
            calendar: calendar
        )
        guard let slot = allocations.first?.scheduledTime else { return nil }

        var updated = task
        updated.scheduledDate = calendar.startOfDay(for: now)
        updated.scheduledTime = slot
        let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
        updated.scheduledEndTime = slot.addingTimeInterval(TimeInterval(duration * 60))
        updated.updatedAt = Date()

        do {
            try await taskRepo.update(updated)
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = updated
            }
            notifyTaskListDidChange()
            return slot
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// Recurrence fields to show when editing an occurrence — reads from the series template.
    public func recurrenceFieldsForEditing(_ task: LifeTask) -> (recurrence: TaskRecurrence, weekdays: [Int]) {
        let source = TaskRecurrenceEngine.recurrenceSource(for: task, in: schedulingContext)
        return (source.recurrenceRule, source.recurrenceWeekdaysValue)
    }

    /// Keep recurrence templates aligned when an occurrence or legacy task is edited.
    private func syncRecurrenceEditsToTemplate(_ task: LifeTask) async throws {
        if let parentId = task.parentTaskId {
            var template = recurrenceTemplates.first(where: { $0.id == parentId })
            if template == nil, let all = try? await taskRepo.getAll(for: task.userId) {
                template = all.first(where: { $0.id == parentId })
            }
            guard var template else { return }

            if task.recurrenceRule != .none {
                template.recurrence = task.recurrence
                template.recurrenceInterval = task.recurrenceInterval
                template.recurrenceWeekdays = task.recurrenceWeekdays
            }
            template.estimatedMinutes = task.estimatedMinutes
            template.updatedAt = Date()
            try await taskRepo.update(template)
            if let index = recurrenceTemplates.firstIndex(where: { $0.id == parentId }) {
                recurrenceTemplates[index] = template
            } else {
                recurrenceTemplates.append(template)
            }

            var occurrence = task
            occurrence.recurrence = nil
            occurrence.recurrenceInterval = nil
            occurrence.recurrenceWeekdays = nil
            try await taskRepo.update(occurrence)
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = occurrence
            }

            let all = try await taskRepo.getAll(for: task.userId)
            let invalidIDs = TaskRecurrenceEngine.invalidScheduledTaskIDs(in: all)
            try await supersedeInvalidScheduledTasks(invalidIDs, in: all)
            return
        }

        guard task.recurrenceRule != .none else { return }

        if TaskRecurrenceEngine.needsLegacyNormalization(task) {
            let (template, occurrence) = TaskRecurrenceEngine.normalizeLegacyRecurringTask(task)
            try await taskRepo.create(template)
            try await taskRepo.update(occurrence)
            recurrenceTemplates.append(template)
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = occurrence
            }
        }
    }

    /// Duplicate a task as a new pending item.
    public func duplicateTask(_ task: LifeTask) {
        var copy = task
        copy.id = UUID().uuidString
        copy.status = .pending
        copy.completedAt = nil
        copy.actualMinutes = nil
        copy.parentTaskId = nil
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.steps = task.steps.map {
            TaskStep(title: $0.title, estimatedMinutes: $0.estimatedMinutes)
        }
        createTask(copy)
    }
    
    /// Use GLM to infer task details from a title.
    public func autoFillDetails(for title: String) async -> TaskAutoFillResult? {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        isAutoFilling = true
        defer { isAutoFilling = false }
        return try? await autoFiller.fill(title: title.trimmingCharacters(in: .whitespaces))
    }
    
    /// Parse tasks from an imported file using GLM.
    public func previewImport(from data: Data, fileName: String) async {
        isImporting = true
        importError = nil
        importPreview = nil
        
        let hasConfiguredKey = !GLMService.shared.keyManagerAccess.allRecords().filter(\.isEnabled).isEmpty
            || GLMService.shared.keyManagerAccess.resolveAPIKey() != nil
        guard hasConfiguredKey else {
            importError = TaskImportError.apiKeyMissing.localizedDescription
            isImporting = false
            return
        }
        
        do {
            importPreview = try await taskImporter.importTasks(from: data, fileName: fileName)
        } catch {
            importError = error.localizedDescription
        }
        
        isImporting = false
    }
    
    /// Create all selected imported tasks.
    public func confirmImport(userId: String) {
        guard let preview = importPreview else { return }
        let selected = preview.tasks.filter(\.selected)
        for draft in selected {
            createTask(draft.toLifeTask(userId: userId))
        }
        importPreview = nil
    }
    
    public func clearImportPreview() {
        importPreview = nil
        importError = nil
    }

    /// Semantic understanding runs once here — LLM when available, deterministic safety merge always.
    private func resolveSemanticProfile(for task: LifeTask) async -> TaskSemanticProfile {
        let deterministic = TaskSemanticProfileBuilder.build(from: task)
        let hasAIKey = !GLMService.shared.keyManagerAccess.allRecords().filter(\.isEnabled).isEmpty
            || GLMService.shared.keyManagerAccess.resolveAPIKey() != nil
        guard hasAIKey else { return deterministic }

        if let llm = try? await semanticAnalyzer.analyze(task: task) {
            return TaskSemanticProfileBuilder.merge(llm: llm, deterministic: deterministic)
        }
        return deterministic
    }

    private func backfillMissingSemanticProfiles(userId: String) async {
        let missing = tasks.filter(\.needsSemanticAnalysis)
        guard !missing.isEmpty else { return }

        for task in missing {
            var enriched = task
            enriched.semanticProfile = await resolveSemanticProfile(for: task)
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = enriched
            }
            try? await taskRepo.update(enriched)
        }
    }
    
    /// Decompose a task into micro-steps and auto-detect recurrence using AI.
    public func decomposeTask(_ task: LifeTask) async {
        decomposingTaskId = task.id
        isDecomposing = true
        defer {
            decomposingTaskId = nil
            isDecomposing = false
        }
        do {
            let result = try await decomposer.decompose(task: task)
            var updatedTask = task
            updatedTask.steps = result.steps
            if updatedTask.parentTaskId == nil,
               updatedTask.recurrence == nil {
                updatedTask.recurrence = result.recurrence
            }
            try await taskRepo.update(updatedTask)
            
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = updatedTask
            }
            selectedTask = updatedTask
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func isDecomposing(taskId: String) -> Bool {
        decomposingTaskId == taskId
    }

    public func timeDisplay(for task: LifeTask, context: TaskFocusStretchResolver.Context? = nil) -> TaskTimeDisplayInfo {
        if let cached = taskTimeDisplays[task.id] {
            return cached
        }
        let resolvedContext = context ?? .fromProfile(energyScore: nil, sleepQuality: nil, executiveCapacity: nil)
        return TaskFocusStretchResolver.displayInfo(for: task, context: resolvedContext)
    }

    public func refreshTimeDisplays(
        for tasks: [LifeTask],
        context: TaskFocusStretchResolver.Context
    ) async {
        for task in tasks {
            var info = TaskFocusStretchResolver.displayInfo(for: task, context: context)
            taskTimeDisplays[task.id] = info
            guard info.needsAIRefinement else { continue }

            loadingTimeDisplayTaskIds.insert(task.id)
            if let refined = await focusStretchRefiner.refine(
                task: task,
                context: context,
                estimatedMinutes: task.estimatedMinutes
            ) {
                taskTimeDisplays[task.id] = refined
            }
            loadingTimeDisplayTaskIds.remove(task.id)
        }
    }

    public func isLoadingTimeDisplay(taskId: String) -> Bool {
        loadingTimeDisplayTaskIds.contains(taskId)
    }
    
    /// Mark a task as completed and schedule the next recurring occurrence when applicable.
    @discardableResult
    public func completeTask(_ task: LifeTask) async -> TaskUndoAction? {
        let activeIndex = tasks.firstIndex(where: { $0.id == task.id })
        let restoredSnapshot = task

        var updated = task
        updated.status = .completed
        updated.completedAt = Date()

        // Optimistic UI — lists update immediately before persistence.
        tasks.removeAll { $0.id == task.id }
        completedToday.insert(updated, at: 0)

        do {
            try await taskRepo.update(updated)

            let undo = TaskUndoAction(
                message: "Task completed",
                kind: .completed(
                    restoredTask: restoredSnapshot,
                    wasInActiveList: activeIndex != nil,
                    activeIndex: activeIndex,
                    spawnedOccurrenceId: nil
                )
            )
            presentUndo(undo)
            NotificationCenter.default.post(name: .analyticsDataDidChange, object: nil, userInfo: ["reason": AnalyticsDataChangeReason.taskCompleted.rawValue])
            notifyTaskListDidChange()
            return undo
        } catch {
            completedToday.removeAll { $0.id == task.id }
            if let activeIndex {
                tasks.insert(restoredSnapshot, at: min(activeIndex, tasks.count))
            } else if !tasks.contains(where: { $0.id == restoredSnapshot.id }) {
                tasks.insert(restoredSnapshot, at: 0)
            }
            self.error = error.localizedDescription
            return nil
        }
    }

    /// Restore a completed task back to active.
    public func markIncomplete(_ task: LifeTask) async {
        var updated = task
        updated.status = .pending
        updated.completedAt = nil
        updated.updatedAt = Date()

        do {
            try await taskRepo.update(updated)
            completedToday.removeAll { $0.id == task.id }
            if !tasks.contains(where: { $0.id == task.id }) {
                tasks.insert(updated, at: 0)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    /// Toggle a step's completion status.
    public func toggleStep(taskId: String, stepId: String) async {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskId }),
              let stepIndex = tasks[taskIndex].steps.firstIndex(where: { $0.id == stepId }) else {
            return
        }
        
        tasks[taskIndex].steps[stepIndex].isCompleted.toggle()
        if tasks[taskIndex].steps[stepIndex].isCompleted {
            tasks[taskIndex].steps[stepIndex].completedAt = Date()
        } else {
            tasks[taskIndex].steps[stepIndex].completedAt = nil
        }
        
        do {
            try await taskRepo.update(tasks[taskIndex])
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    /// Start a task (set to in progress).
    public func startTask(_ task: LifeTask) async {
        var updated = task
        updated.status = .inProgress
        updated.updatedAt = Date()
        
        do {
            try await taskRepo.update(updated)
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    /// Delete a task — instant UI removal, persisted before refresh listeners fire.
    @discardableResult
    public func deleteTask(_ task: LifeTask) async -> TaskUndoAction? {
        let idsToDelete = deletionTargets(for: task)
        let activeIndex = tasks.firstIndex(where: { $0.id == task.id })
        let completedIndex = completedToday.firstIndex(where: { $0.id == task.id })
        let wasInActive = activeIndex != nil
        let wasInCompleted = completedIndex != nil

        // Capture schedule geometry before removal (auction needs the freed gap).
        let freedGap = Self.freedGap(from: task)
        let wasRecovery = task.tags.contains("recovery-block") || task.tags.contains("brain-locked")
        let wasAnchored = task.timeConstraintValue == .anchored || task.isFixedTimeEvent

        tasks.removeAll { idsToDelete.contains($0.id) }
        completedToday.removeAll { idsToDelete.contains($0.id) }
        recurrenceTemplates.removeAll { idsToDelete.contains($0.id) }

        for id in idsToDelete {
            do {
                try await taskRepo.delete(id)
            } catch {
                self.error = error.localizedDescription
            }
        }

        // Sabotage override learning + cool-down when user breaks a recovery lock.
        if wasRecovery {
            ParkedTaskRecoveryService.shared.handleRecoveryBlockOverride(task: task)
        } else if wasAnchored, let gap = freedGap, gap.minutes >= 45 {
            // Product trigger: freed anchored time → auction / possible sabotage.
            let streak = HighLoadDayEvaluator.consecutiveHighLoadDays(tasks: tasks + completedToday)
            _ = ParkedTaskRecoveryService.shared.auction(
                gapMinutes: gap.minutes,
                energy: .moderate,
                consecutiveHighLoadDays: streak,
                gapStart: gap.start,
                day: gap.day,
                userId: task.userId,
                tasksVM: self
            )
        }

        let undo = TaskUndoAction(
            message: "Task deleted",
            kind: .deleted(
                task: task,
                wasInActiveList: wasInActive,
                activeIndex: activeIndex,
                wasInCompletedList: wasInCompleted,
                completedIndex: completedIndex
            )
        )
        presentUndo(undo)
        notifyTaskListDidChange()
        return undo
    }

    /// Geometry of a deleted block for gap auction.
    private static func freedGap(from task: LifeTask) -> (start: Date, day: Date, minutes: Int)? {
        guard let start = task.scheduledTime else { return nil }
        let cal = Calendar.current
        let day = task.scheduledDate.map { cal.startOfDay(for: $0) } ?? cal.startOfDay(for: start)
        let minutes: Int
        if let end = task.scheduledEndTime {
            minutes = max(TaskDurationPolicy.minimumMinutes, Int(end.timeIntervalSince(start) / 60.0))
        } else {
            minutes = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
        }
        return (start, day, minutes)
    }

    /// Deletes recurring occurrences together with their template so sync cannot recreate them.
    private func deletionTargets(for task: LifeTask) -> Set<String> {
        var ids: Set<String> = [task.id]

        if let parentId = task.parentTaskId {
            ids.insert(parentId)
            ids.formUnion(tasks.filter { $0.parentTaskId == parentId }.map(\.id))
            ids.formUnion(completedToday.filter { $0.parentTaskId == parentId }.map(\.id))
        } else if TaskRecurrenceEngine.isRecurrenceTemplate(task) {
            ids.formUnion(tasks.filter { $0.parentTaskId == task.id }.map(\.id))
            ids.formUnion(completedToday.filter { $0.parentTaskId == task.id }.map(\.id))
        } else if task.recurrenceRule != .none {
            if let template = recurrenceTemplates.first(where: {
                $0.title.caseInsensitiveCompare(task.title) == .orderedSame
            }) {
                ids.insert(template.id)
                ids.formUnion(tasks.filter { $0.parentTaskId == template.id }.map(\.id))
                ids.formUnion(completedToday.filter { $0.parentTaskId == template.id }.map(\.id))
            }
        }

        return ids
    }

    /// Materializes life commitment tasks from compiled LifeModel (gym, music, etc.).
    public func ensureLifeCommitmentTasks(
        userId: String,
        model: LifeModel,
        date: Date = Date(),
        calendar: Calendar = .current
    ) async {
        guard !userId.isEmpty, model.hasContent else { return }

        await dedupeLifeCommitmentTasks(userId: userId, model: model, calendar: calendar)

        let assembly = DayAssembler.assemble(
            model: model,
            existingTasks: tasks,
            completedToday: completedToday,
            userId: userId,
            date: date,
            calendar: calendar
        )

        for var task in assembly.tasksToCreate {
            task.userId = userId
            task.recurrence = nil
            task.isRecurrenceTemplate = false
            tasks.insert(task, at: 0)
            do {
                try await taskRepo.create(task)
            } catch {
                tasks.removeAll { $0.id == task.id }
                self.error = error.localizedDescription
            }
        }

        if !assembly.tasksToCreate.isEmpty {
            applySnapshot(taskRepo.localSnapshot(for: userId), logSource: "life-commitments")
            notifyTaskListDidChange()
        }

        await reconcileTodaySchedule(userId: userId, model: model, date: date, calendar: calendar)
    }

    /// Repairs same-day schedule overlaps and snaps life commitments to LifeModel block times.
    public func reconcileTodaySchedule(
        userId: String,
        model: LifeModel? = LifeModelStore.load(),
        date: Date = Date(),
        calendar: Calendar = .current
    ) async {
        guard !userId.isEmpty else { return }

        // Day-boundary Reaper: expire/skip/supersede yesterday before today's cascade.
        await sweepPreviousDayIfNeeded(userId: userId, now: date, calendar: calendar)

        let day = calendar.startOfDay(for: date)
        let activePool = tasks.filter { task in
            guard task.status.isActive, task.scheduledTime != nil, let scheduledDate = task.scheduledDate else {
                return false
            }
            return calendar.isDate(scheduledDate, inSameDayAs: day)
        }
        guard !activePool.isEmpty else { return }

        let result = DayScheduleReconciler.reconcile(
            tasks: activePool,
            on: day,
            model: model,
            calendar: calendar
        )
        guard !result.changedTaskIDs.isEmpty else { return }

        for updated in result.tasks where result.changedTaskIDs.contains(updated.id) {
            if let index = tasks.firstIndex(where: { $0.id == updated.id }) {
                tasks[index] = updated
            }
            if let index = completedToday.firstIndex(where: { $0.id == updated.id }) {
                completedToday[index] = updated
            }
            do {
                try await taskRepo.update(updated)
            } catch {
                self.error = error.localizedDescription
            }
        }

        notifyTaskListDidChange()
    }

    /// Run once per calendar day: reaper on yesterday's incomplete tasks.
    private func sweepPreviousDayIfNeeded(
        userId: String,
        now: Date,
        calendar: Calendar
    ) async {
        let key = "lookafter.lastReaperSweep.\(userId)"
        let todayKey = TelemetryLogRotation.dayKey(for: now, calendar: calendar)
        if UserDefaults.standard.string(forKey: key) == todayKey { return }

        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else {
            return
        }
        let pool = tasks + completedToday
        let result = DayScheduleReconciler.sweepDayBoundary(
            tasks: pool,
            from: yesterday,
            to: now,
            now: now,
            calendar: calendar,
            parkedQueue: ParkedTaskQueueStore.shared
        )
        for updated in result.tasks where result.changedTaskIDs.contains(updated.id) {
            if let index = tasks.firstIndex(where: { $0.id == updated.id }) {
                if updated.status.isActive {
                    tasks[index] = updated
                } else {
                    tasks.remove(at: index)
                }
            }
            if let index = completedToday.firstIndex(where: { $0.id == updated.id }) {
                if updated.status == .completed {
                    completedToday[index] = updated
                } else {
                    completedToday.remove(at: index)
                }
            }
            do {
                try await taskRepo.update(updated)
            } catch {
                self.error = error.localizedDescription
                return
            }
        }
        UserDefaults.standard.set(todayKey, forKey: key)
    }

    /// Removes duplicate creative commitment tasks and recurring templates that spawn multiple music tasks per day.
    public func dedupeLifeCommitmentTasks(
        userId: String,
        model: LifeModel,
        calendar: Calendar = .current
    ) async {
        guard !userId.isEmpty else { return }

        let all: [LifeTask]
        do {
            all = try await taskRepo.getAll(for: userId)
        } catch {
            self.error = error.localizedDescription
            return
        }

        let creativeTags = Set(
            model.commitments
                .filter { $0.lifeArea == .creativity }
                .map { model.commitmentID(for: $0.title) }
        )

        var idsToDelete: Set<String> = []

        for task in all where task.isLifeCommitmentTask {
            if task.isRecurrenceTemplateTask || task.recurrenceRule != .none {
                idsToDelete.formUnion(deletionTargets(for: task))
            }
        }

        let activeCreative = all.filter { task in
            guard task.status.isActive, !idsToDelete.contains(task.id) else { return false }
            if MultiDayTaskTags.isSlice(task), task.lifeArea == .creativity {
                return true
            }
            if task.isLifeCommitmentTask {
                return task.tags.contains(where: creativeTags.contains) || task.lifeArea == .creativity
            }
            return task.lifeArea == .creativity && task.scheduledTime != nil
        }

        let grouped = Dictionary(grouping: activeCreative) { task -> Date in
            calendar.startOfDay(for: task.scheduledDate ?? task.scheduledTime ?? task.createdAt)
        }

        for (_, group) in grouped where group.count > 1 {
            let keeper = group.min { lhs, rhs in
                if MultiDayTaskTags.isSlice(lhs) != MultiDayTaskTags.isSlice(rhs) {
                    return MultiDayTaskTags.isSlice(lhs) && !MultiDayTaskTags.isSlice(rhs)
                }
                if lhs.isLifeCommitmentTask != rhs.isLifeCommitmentTask {
                    return lhs.isLifeCommitmentTask && !rhs.isLifeCommitmentTask
                }
                if lhs.isFixedTimeEvent != rhs.isFixedTimeEvent { return lhs.isFixedTimeEvent && !rhs.isFixedTimeEvent }
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.createdAt < rhs.createdAt
            }
            for task in group where task.id != keeper?.id {
                idsToDelete.insert(task.id)
            }
        }

        guard !idsToDelete.isEmpty else {
            await fixLifeCommitmentFixedTimes(userId: userId, in: all)
            await reconcileTodaySchedule(userId: userId, model: model, calendar: calendar)
            return
        }

        for id in idsToDelete {
            guard all.contains(where: { $0.id == id }) else { continue }
            tasks.removeAll { $0.id == id }
            completedToday.removeAll { $0.id == id }
            do {
                try await taskRepo.delete(id)
            } catch {
                self.error = error.localizedDescription
            }
        }

        applySnapshot(taskRepo.localSnapshot(for: userId), logSource: "life-commitment-dedupe")
        notifyTaskListDidChange()
        await fixLifeCommitmentFixedTimes(userId: userId, in: all.filter { !idsToDelete.contains($0.id) })
        await reconcileTodaySchedule(userId: userId, model: model, calendar: calendar)
    }

    /// Ensures existing life-commitment tasks with block times stay fixed — not moved by AI replan.
    private func fixLifeCommitmentFixedTimes(userId: String, in tasks: [LifeTask]) async {
        for var task in tasks where task.isLifeCommitmentTask && task.scheduledTime != nil {
            guard task.schedulingMode != .fixedTime else { continue }
            task.schedulingMode = .fixedTime
            do {
                try await taskRepo.update(task)
            } catch {
                self.error = error.localizedDescription
            }
        }
        applySnapshot(taskRepo.localSnapshot(for: userId), logSource: "life-commitment-fixed-times")
    }

    /// Adds standard daily routines (meals, hygiene, review) when missing from the task list.
    public func ensureDailyRoutineTasks(userId: String) async {
        guard !userId.isEmpty else { return }

        if LifeModelStore.hasCompiledModel { return }

        await removeRetiredRoutineTasks(userId: userId)

        let routine = OnboardingTaskSeeder.dailyRoutineTasks()
        guard !routine.isEmpty else { return }

        let existingTitles = Set(
            (try? await taskRepo.getAll(for: userId))?
                .map { $0.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) } ?? []
        )

        for var seedTask in routine where !existingTitles.contains(seedTask.title.lowercased()) {
            seedTask.userId = userId
            if seedTask.recurrenceRule != .none {
                await persistRecurringTask(seedTask, decompose: false)
            } else {
                do {
                    try await taskRepo.create(seedTask)
                    tasks.insert(seedTask, at: 0)
                } catch {
                    print("[Tasks] daily routine seed failed: \(error.localizedDescription)")
                }
            }
        }

        do {
            try await syncRecurringOccurrences(userId: userId)
            applySnapshot(taskRepo.localSnapshot(for: userId), logSource: "daily-routine-seed")
        } catch {
            print("[Tasks] daily routine recurrence sync failed: \(error.localizedDescription)")
        }
    }

    /// Removes routines that are no longer tasks (e.g. Journal moved to Timeline reflection).
    public func removeRetiredRoutineTasks(userId: String) async {
        guard !userId.isEmpty else { return }

        let retired = OnboardingTaskSeeder.retiredRoutineTitles
        let snapshot = (try? await taskRepo.getAll(for: userId)) ?? tasks + completedToday
        let targets = snapshot.filter {
            retired.contains($0.title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
        }

        for task in targets {
            _ = await deleteTask(task)
        }
    }

    public func performUndo() async {
        undoDismissTask?.cancel()
        undoDismissTask = nil
        isUndoToastVisible = false
        undoToastMessage = ""
        guard let action = pendingUndo else { return }
        pendingUndo = nil

        switch action.kind {
        case .completed(let restoredTask, let wasInActive, let activeIndex, let spawnedId):
            if let spawnedId {
                tasks.removeAll { $0.id == spawnedId }
                try? await taskRepo.delete(spawnedId)
            }

            completedToday.removeAll { $0.id == restoredTask.id }

            var activeTask = restoredTask
            activeTask.status = .pending
            activeTask.completedAt = nil

            if wasInActive {
                if let activeIndex, activeIndex <= tasks.count {
                    tasks.insert(activeTask, at: min(activeIndex, tasks.count))
                } else {
                    tasks.insert(activeTask, at: 0)
                }
            }

            try? await taskRepo.update(activeTask)

        case .deleted(let task, let wasInActive, let activeIndex, let wasInCompleted, let completedIndex):
            if wasInActive {
                if let activeIndex, activeIndex <= tasks.count {
                    tasks.insert(task, at: min(activeIndex, tasks.count))
                } else {
                    tasks.insert(task, at: 0)
                }
            }
            if wasInCompleted {
                if let completedIndex, completedIndex <= completedToday.count {
                    completedToday.insert(task, at: min(completedIndex, completedToday.count))
                } else {
                    completedToday.append(task)
                }
            }
            try? await taskRepo.create(task)
        }
        notifyTaskListDidChange()
    }
    
    public func clearPendingUndo() {
        dismissUndoToast()
    }

    public func dismissUndoToast() {
        undoDismissTask?.cancel()
        undoDismissTask = nil
        isUndoToastVisible = false
        undoToastMessage = ""
        pendingUndo = nil
    }

    private func presentUndo(_ action: TaskUndoAction) {
        undoDismissTask?.cancel()
        pendingUndo = action
        undoToastMessage = "\(action.message) • Undo"
        isUndoToastVisible = true

        undoDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.expireUndoIfMatching(action.id)
            }
        }
    }

    private func expireUndoIfMatching(_ actionID: String) {
        guard pendingUndo?.id == actionID else { return }
        isUndoToastVisible = false
        undoToastMessage = ""
        pendingUndo = nil
        undoDismissTask = nil
    }
}

/// ViewModel for the Universal Inbox.
@MainActor
public final class InboxViewModel: ObservableObject {
    
    @Published public var items: [InboxItem] = []
    @Published public var unprocessedCount: Int = 0
    @Published public var isLoading: Bool = false
    @Published public var isProcessing: Bool = false
    @Published public var error: String?
    
    private let inboxRepo: InboxRepository
    private let glm: GLMService
    private var currentUserId: String = ""
    public var onCreateTask: ((InboxTaskDraft) async throws -> Void)?

    public init(inboxRepo: InboxRepository? = nil, glmService: GLMService = .shared) {
        self.inboxRepo = inboxRepo ?? InboxRepository()
        self.glm = glmService
    }
    
    /// Load all inbox items.
    public func loadItems(userId: String) async {
        currentUserId = userId
        if FreshInstallGuard.isActive {
            resetInMemoryState()
            return
        }
        isLoading = true
        do {
            items = try await inboxRepo.getAll(for: userId)
            unprocessedCount = items.filter { $0.status == .unprocessed }.count
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
    
    /// Quick capture — add a text item to inbox.
    public func quickCapture(text: String) async {
        let item = InboxItem(content: text, type: .text)
        do {
            try await inboxRepo.create(item)
            items.insert(item, at: 0)
            unprocessedCount += 1
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Capture and silently route via AI — executive capture path.
    public func captureAndProcess(text: String) async {
        let item = InboxItem(content: text, type: .text)
        do {
            try await inboxRepo.create(item)
            items.insert(item, at: 0)
            await processItem(item)
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    /// Process an inbox item with AI.
    public func processItem(_ item: InboxItem) async {
        isProcessing = true
        
        let prompt = LookAfterPrompts.inboxProcessingPrompt(item: item)

        do {
            let response = try await glm.complete(
                prompt: prompt,
                systemPrompt: LookAfterPrompts.inboxProcessingSystem,
                tier: .standard
            )
            
            let cleaned = response
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let data = cleaned.data(using: .utf8),
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                var updated = item
                updated.status = .categorized
                updated.aiSummary = json["summary"] as? String
                updated.aiSuggestedAction = json["suggestedAction"] as? String
                updated.processedAt = Date()
                
                if let areaStr = json["lifeArea"] as? String {
                    updated.lifeArea = LifeArea.allCases.first { $0.rawValue == areaStr }
                }
                if let priorityStr = json["priority"] as? String {
                    updated.suggestedPriority = Priority.allCases.first { $0.label == priorityStr }
                }

                try await inboxRepo.update(updated)

                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index] = updated
                }
                unprocessedCount = items.filter { $0.status == .unprocessed }.count

                if let action = json["suggestedAction"] as? String,
                   action.lowercased() != "archive",
                   let title = json["taskTitle"] as? String,
                   !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let handler = onCreateTask {
                    let difficultyStr = json["taskDifficulty"] as? String
                    let difficulty = TaskDifficulty.allCases.first { $0.rawValue == difficultyStr }
                    let minutes = json["estimatedMinutes"] as? Int ?? 15
                    let draft = InboxTaskDraft(
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        lifeArea: updated.lifeArea,
                        priority: updated.suggestedPriority,
                        difficulty: difficulty,
                        estimatedMinutes: TaskDurationPolicy.clamp(minutes, allowShortTasks: true)
                    )
                    try await handler(draft)
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
        
        isProcessing = false
    }
    
    /// Delete an inbox item.
    public func deleteItem(_ item: InboxItem) async {
        do {
            try await inboxRepo.delete(item.id)
            items.removeAll { $0.id == item.id }
            unprocessedCount = items.filter { $0.status == .unprocessed }.count
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Clears inbox presentation state after factory reset.
    public func resetInMemoryState() {
        items = []
        unprocessedCount = 0
        isLoading = false
        isProcessing = false
        error = nil
    }
}
