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
    /// Bumps whenever task rows mutate — drives TaskListView cache invalidation.
    @Published public private(set) var tasksContentRevision = 0
    
    private let taskRepo: TaskStoring
    private let taskStore: TaskStore?
    private let decomposer: TaskDecomposer
    private let autoFiller: TaskAutoFiller
    private let taskImporter: TaskImporter
    private let semanticAnalyzer: TaskSemanticAnalyzer
    private let focusStretchRefiner = TaskFocusStretchRefiner()
    private var timeDisplayFingerprints: [String: TimeDisplayFingerprint] = [:]
    private var undoDismissTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var didCompactTaskStorage = false
    /// Blocks store-driven snapshot overwrites while a user edit is persisting.
    private var isSuppressingStoreSync = false
    /// Blocks debounced reconcile while a batched schedule sync is running.
    private var isBatchScheduleSync = false
    private var lastScheduleSyncFinishedAt: Date?
    private static let scheduleSyncCoalesceInterval: TimeInterval = 2
    /// Prevents re-entrant reconcile loops.
    private var isReconciling = false
    private var pendingForceReplan = false
    private var pendingReconcileAfterCurrent = false
    private var reconcileDebounceTask: Task<Void, Never>?
    private static let reconcileDebounceNanoseconds: UInt64 = 300_000_000
    private static let semanticAnalysisTimeoutSeconds: TimeInterval = 8
    private lazy var _scheduleMutation = ScheduleMutationService(viewModel: self)

    @Published public private(set) var dayScheduleSnapshot: DayScheduleSnapshot = .empty

    /// Single write gate for schedule field mutations.
    public var scheduleMutation: ScheduleMutationService { _scheduleMutation }
    
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
    /// Schedule repair runs via `syncScheduleAndReconcileToday` on context refresh, not here.
    public func loadTasks(userId: String, syncRecurrence: Bool = false) async {
        let generation = loadGeneration + 1
        loadGeneration = generation

        // Cold launch: hydrate tasks.sqlite off the main thread before first snapshot read.
        await taskRepo.warmLocalCache(for: userId)
        guard generation == loadGeneration else { return }

        await compactTaskStorageIfNeeded(userId: userId)
        guard generation == loadGeneration else { return }

        await normalizeMidnightSentinelsInStorage(userId: userId)
        guard generation == loadGeneration else { return }

        applySnapshot(taskRepo.localSnapshot(for: userId), logSource: "launch-cache")

        let showSpinner = tasks.isEmpty && completedToday.isEmpty
        if showSpinner { isLoading = true }

        do {
            _ = try await taskRepo.getTaskLists(for: userId)
            guard generation == loadGeneration else { return }
            if syncRecurrence {
                try await syncRecurringOccurrences(userId: userId)
                guard generation == loadGeneration else { return }
            }
            applySnapshot(taskRepo.localSnapshot(for: userId), logSource: "remote-sync")
            await repairMidnightSchedulesOnLoad(userId: userId)
            await backfillMissingSemanticProfiles(userId: userId)
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

    /// Applies the in-memory TaskStore snapshot without re-reading disk.
    public func syncFromTaskStore() {
        guard let taskStore else { return }
        guard !isSuppressingStoreSync else { return }
        applySnapshot(taskStore.snapshot, logSource: "task-store-sync")
    }

    private func bumpTasksRevision() {
        tasksContentRevision &+= 1
    }

    private func notifyTaskListDidChange() {
        guard taskStore == nil else { return }
        NotificationCenter.default.post(name: .taskListDidChange, object: nil)
    }

    private func notifyScheduleDidChange() {
        NotificationCenter.default.post(name: .scheduleDidChange, object: nil)
    }

    /// Debounced entry point for reconcile after task list mutations.
    public func requestDebouncedScheduleReconcile(userId: String, immediate: Bool = false) {
        if isBatchScheduleSync || isReconciling { return }
        if let lastScheduleSyncFinishedAt,
           Date().timeIntervalSince(lastScheduleSyncFinishedAt) < Self.scheduleSyncCoalesceInterval {
            return
        }
        reconcileDebounceTask?.cancel()
        reconcileDebounceTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(nanoseconds: Self.reconcileDebounceNanoseconds)
            }
            guard !Task.isCancelled, let self else { return }
            await self.performScheduleReconcile(userId: userId)
        }
    }

    private func performScheduleReconcile(userId: String) async {
        if isReconciling || isBatchScheduleSync {
            pendingReconcileAfterCurrent = true
            return
        }
        await syncScheduleAndReconcileToday(userId: userId, forceRecurrenceSync: true, localRecurrenceOnly: true)
    }

    public func scheduleFieldsChanged(from previous: LifeTask?, to updated: LifeTask) -> Bool {
        previous?.scheduledDate != updated.scheduledDate
            || previous?.scheduledTime != updated.scheduledTime
            || previous?.scheduledEndTime != updated.scheduledEndTime
            || previous?.schedulingMode != updated.schedulingMode
            || previous?.timeConstraint != updated.timeConstraint
    }

    /// Post-reconcile scheduled tasks for today when snapshot is fresh; otherwise falls back to presenter filter.
    public func reconciledScheduledTasksForToday(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [LifeTask] {
        let dayStart = calendar.startOfDay(for: now)
        if calendar.isDate(dayScheduleSnapshot.day, inSameDayAs: dayStart),
           !dayScheduleSnapshot.tasks.isEmpty {
            return dayScheduleSnapshot.activeScheduledTasks
        }
        let allTasks = tasks + completedToday + recurrenceTemplates
        return LifeTimelinePresenter.tasksScheduledForToday(
            from: tasks.filter { $0.status.isActive },
            allTasks: allTasks,
            now: now,
            calendar: calendar
        )
    }

    private func publishDayScheduleSnapshot(day: Date, changedIDs: Set<String>, calendar: Calendar) {
        let dayStart = calendar.startOfDay(for: day)
        let scheduled = tasks.filter { task in
            guard task.status.isActive, let scheduledDate = task.scheduledDate else { return false }
            return calendar.isDate(scheduledDate, inSameDayAs: dayStart)
        }
        dayScheduleSnapshot = DayScheduleSnapshot(
            day: dayStart,
            tasks: scheduled,
            reconciledAt: Date(),
            changedTaskIDs: changedIDs
        )
    }

    /// Strips persisted `00:00` sentinels across all local tasks before anchor repair.
    private func normalizeMidnightSentinelsInStorage(userId: String) async {
        guard !userId.isEmpty else { return }
        let calendar = Calendar.current
        var changed = false
        for task in taskRepo.localAllTasks(for: userId) {
            let isTemplate = TaskRecurrenceEngine.isRecurrenceTemplate(task)
            guard task.status.isActive || isTemplate else { continue }
            guard TaskScheduleInterval.isPlaceholderMidnightSchedule(for: task, calendar: calendar) else { continue }
            var normalized = task
            ScheduleNormalization.normalizeFields(&normalized, calendar: calendar)
            if !isTemplate {
                normalized = TaskConstraintAlignment.align(normalized)
            }
            normalized.updatedAt = Date()
            do {
                try await taskRepo.update(normalized)
                changed = true
#if DEBUG
                print("[Tasks] stripped midnight sentinel id=\(task.id.prefix(8)) title=\"\(task.title)\"")
#endif
            } catch {
                self.error = error.localizedDescription
            }
        }
        if changed {
            taskStore?.refreshLocal(userId: userId)
            applySnapshot(taskRepo.localSnapshot(for: userId), logSource: "midnight-normalize", authoritative: true)
        }
    }

    /// Aligns legacy schedulingMode/timeConstraint desync across in-memory tasks.
    public func migrateConstraintFieldsIfNeeded(userId: String) async {
        var changed = false
        let all = taskRepo.localAllTasks(for: userId)
        for task in all where task.status.isActive && !TaskRecurrenceEngine.isRecurrenceTemplate(task) {
            var aligned = TaskConstraintAlignment.align(task)
            guard aligned.timeConstraint != task.timeConstraint
                || aligned.schedulingMode != task.schedulingMode else { continue }
            do {
                try await taskRepo.update(aligned)
                changed = true
            } catch {
                self.error = error.localizedDescription
            }
        }
        if changed, !userId.isEmpty {
            taskStore?.refreshLocal(userId: userId)
            applySnapshot(taskRepo.localSnapshot(for: userId), logSource: "constraint-migration")
        }
    }

    private func applySnapshot(_ snapshot: TaskListSnapshot, logSource: String, authoritative: Bool = false) {
        if authoritative {
            tasks = snapshot.active
            completedToday = snapshot.completedToday
            recurrenceTemplates = snapshot.templates
        } else {
            tasks = Self.mergeTasksPreservingNewerEdits(existing: tasks, incoming: snapshot.active)
            completedToday = Self.mergeTasksPreservingNewerEdits(
                existing: completedToday,
                incoming: snapshot.completedToday
            )
            recurrenceTemplates = Self.mergeTasksPreservingNewerEdits(
                existing: recurrenceTemplates,
                incoming: snapshot.templates
            )
        }
        bumpTasksRevision()
#if DEBUG
        print("[Tasks] VM apply snapshot source=\(logSource) authoritative=\(authoritative) active=\(tasks.count) completedToday=\(completedToday.count) templates=\(recurrenceTemplates.count)")
#endif
    }

    /// Keeps in-memory edits when a stale snapshot refresh races with an optimistic update.
    private static func mergeTasksPreservingNewerEdits(existing: [LifeTask], incoming: [LifeTask]) -> [LifeTask] {
        var byID = Dictionary.uniquingFirstValue(incoming.map { ($0.id, $0) })
        for task in existing {
            if let snapshotTask = byID[task.id] {
                if hasMidnightSentinel(task), !hasMidnightSentinel(snapshotTask) {
                    byID[task.id] = snapshotTask
                } else if task.updatedAt >= snapshotTask.updatedAt {
                    byID[task.id] = task
                }
            } else if task.status.isActive, !hasMidnightSentinel(task) {
                byID[task.id] = task
            }
        }
        let incomingOrder = incoming.map(\.id)
        var merged = incomingOrder.compactMap { byID[$0] }
        let extras = byID.values.filter { task in
            !incomingOrder.contains(task.id)
        }
        merged.append(contentsOf: extras.sorted { $0.priority > $1.priority })
        return merged
    }

    private static func hasMidnightSentinel(_ task: LifeTask) -> Bool {
        TaskScheduleInterval.isPlaceholderMidnightSchedule(for: task)
    }

    /// Normalize legacy recurring tasks, remove invalid day instances, and materialize today's occurrences.
    public func syncRecurringSchedule(
        userId: String,
        force: Bool = false,
        localOnly: Bool = false,
        deferSnapshot: Bool = false
    ) async {
        guard !userId.isEmpty else { return }
        if !force,
           let lastRecurrenceSyncAt,
           Date().timeIntervalSince(lastRecurrenceSyncAt) < Self.recurrenceSyncMinimumInterval {
            return
        }
        do {
            try await syncRecurringOccurrences(userId: userId, localOnly: localOnly)
            lastRecurrenceSyncAt = Date()
            if !deferSnapshot {
                applySnapshot(taskRepo.localSnapshot(for: userId), logSource: "recurrence-sync")
            }
        } catch {
#if DEBUG
            print("[Tasks] recurrence sync failed: \(error.localizedDescription)")
#endif
        }
    }

    /// Single refresh path: materialize recurrence, repair overlaps, persist only when needed.
    public func syncScheduleAndReconcileToday(
        userId: String,
        model: LifeModel? = LifeModelStore.load(),
        forceRecurrenceSync: Bool = false,
        localRecurrenceOnly: Bool = false
    ) async {
        guard !userId.isEmpty else { return }
        isBatchScheduleSync = true
        isSuppressingStoreSync = true
        taskStore?.beginSuppressingNotifications()
        defer {
            isBatchScheduleSync = false
            isSuppressingStoreSync = false
            lastScheduleSyncFinishedAt = Date()
            taskStore?.endSuppressingNotifications()
            taskStore?.refreshLocal(userId: userId)
            applySnapshot(
                taskRepo.localSnapshot(for: userId),
                logSource: "schedule-sync-final",
                authoritative: true
            )
            notifyScheduleDidChange()
            NotificationCenter.default.post(name: .taskListDidChange, object: nil)
        }
        await syncRecurringSchedule(
            userId: userId,
            force: forceRecurrenceSync,
            localOnly: localRecurrenceOnly,
            deferSnapshot: true
        )
        await reconcileTodaySchedule(
            userId: userId,
            model: model,
            postScheduleNotification: true,
            deferSnapshot: true
        )
    }

    private static let recurrenceSyncMinimumInterval: TimeInterval = 45
    private var lastRecurrenceSyncAt: Date?

    /// Normalize legacy recurring tasks and materialize today's occurrences.
    private func syncRecurringOccurrences(userId: String, localOnly: Bool = false) async throws {
        var all = localOnly ? reloadLocalTasks(for: userId) : try await taskRepo.getAll(for: userId)

        for task in all where TaskRecurrenceEngine.needsLegacyNormalization(task) {
            let matchingTemplate = all.first {
                TaskRecurrenceEngine.isRecurrenceTemplate($0)
                    && $0.title.caseInsensitiveCompare(task.title) == .orderedSame
                    && $0.id != task.id
            }
            if matchingTemplate != nil {
                try await taskRepo.delete(task.id)
#if DEBUG
                print("[Tasks] removed duplicate legacy recurring id=\(task.id.prefix(8)) title=\"\(task.title)\"")
#endif
                continue
            }

            let alreadyLinked = all.contains { $0.parentTaskId == task.id }
            guard !alreadyLinked else { continue }

            let (template, occurrence) = TaskRecurrenceEngine.normalizeLegacyRecurringTask(task)
            try await taskRepo.create(template)
            try await taskRepo.update(occurrence)
#if DEBUG
            print("[Tasks] normalized legacy recurring template=\(template.id.prefix(8))")
#endif
        }

        all = reloadLocalTasks(for: userId)
        try await applyRecurrenceTemplateDedupe(userId: userId)
        all = reloadLocalTasks(for: userId)

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
        all = reloadLocalTasks(for: userId)

        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)
        let materializeDays = [today] + (tomorrow.map { [$0] } ?? [])
        try await reactivateSupersededOccurrences(userId: userId, days: materializeDays, in: all)
        all = reloadLocalTasks(for: userId)

        let missing = TaskRecurrenceEngine.missingOccurrences(for: all, on: Date())
            .filter { !$0.isLifeCommitmentTask }
        for var occurrence in missing {
            occurrence.userId = userId
            try await taskRepo.create(occurrence)
#if DEBUG
            print("[Tasks] scheduler created occurrence template=\(occurrence.parentTaskId?.prefix(8) ?? "?")")
#endif
        }

        if let tomorrow {
            all = reloadLocalTasks(for: userId)
            let tomorrowMissing = TaskRecurrenceEngine.missingOccurrences(for: all, on: tomorrow)
                .filter { !$0.isLifeCommitmentTask }
            for var occurrence in tomorrowMissing {
                occurrence.userId = userId
                try await taskRepo.create(occurrence)
#if DEBUG
                print("[Tasks] scheduler created tomorrow occurrence template=\(occurrence.parentTaskId?.prefix(8) ?? "?")")
#endif
            }
        }

        try await assignRoutineAnchorTimes(
            userId: userId,
            days: materializeDays,
            model: LifeModelStore.load()
        )

        // Re-run after materialization in case stale rows were merged back in.
        all = reloadLocalTasks(for: userId)
        let remainingInvalid = TaskRecurrenceEngine.invalidScheduledTaskIDs(in: all)
        try await supersedeInvalidScheduledTasks(remainingInvalid, in: all)

        all = reloadLocalTasks(for: userId)
        var staleDuplicates = Set<String>()
        for day in materializeDays {
            staleDuplicates.formUnion(
                TaskSeriesResolver.staleActiveSeriesIDs(in: all, on: day)
            )
        }
        try await supersedeInvalidScheduledTasks(Array(staleDuplicates), in: all, includingLifeCommitments: true)

        if let model = LifeModelStore.load(), model.hasContent {
            all = reloadLocalTasks(for: userId)
            await dedupeLifeCommitmentTasks(userId: userId, model: model, existingTasks: all)
        }
    }

    /// Reads the warm in-memory task pool — avoids redundant Firestore round-trips during recurrence sync.
    private func reloadLocalTasks(for userId: String) -> [LifeTask] {
        taskRepo.localAllTasks(for: userId)
    }

    /// Store rows plus optimistic in-memory edits — prevents duplicate recurrence materialization.
    private func mergedLocalTasks(for userId: String) -> [LifeTask] {
        var byID = Dictionary.uniquingFirstValue(reloadLocalTasks(for: userId).map { ($0.id, $0) })
        for task in tasks + completedToday + recurrenceTemplates {
            guard task.userId == userId || userId.isEmpty else { continue }
            byID[task.id] = task
        }
        return Array(byID.values)
    }

    /// Shrinks bloated local recurrence history off the main thread — once per session unless count stays high.
    @discardableResult
    public func compactTaskStorageIfNeeded(userId: String) async -> Int {
        guard !userId.isEmpty else { return 0 }
        let localCount = taskRepo.localAllTasks(for: userId).count
        guard !didCompactTaskStorage || localCount > 80 else { return 0 }
        let removed = await taskRepo.compactRecurrenceStorageAsync(for: userId, retentionDays: 7)
        didCompactTaskStorage = true
        if removed > 0 {
            applySnapshot(taskRepo.localSnapshot(for: userId), logSource: "compact")
        }
        return removed
    }

    /// Synchronous compaction — tests and explicit maintenance only; avoid on refresh paths.
    @discardableResult
    public func compactTaskStorage(userId: String) -> Int {
        guard !userId.isEmpty else { return 0 }
        let removed = taskRepo.compactRecurrenceStorage(for: userId, retentionDays: 7)
        if removed > 0 {
            applySnapshot(taskRepo.localSnapshot(for: userId), logSource: "compact")
        }
        return removed
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
                guard !TaskRecurrenceEngine.isSeriesFulfilled(
                    on: dayStart,
                    for: template,
                    in: allTasks,
                    calendar: calendar
                ) else { continue }
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

    /// Snap date-only routine occurrences to profile / life-model anchor windows.
    private func assignRoutineAnchorTimes(
        userId: String,
        days: [Date],
        model: LifeModel?
    ) async throws {
        let calendar = Calendar.current
        var all = reloadLocalTasks(for: userId)

        for day in days {
            let dayStart = calendar.startOfDay(for: day)
            for index in all.indices {
                guard all[index].status.isActive else { continue }
                guard let scheduledDate = all[index].scheduledDate,
                      calendar.isDate(scheduledDate, inSameDayAs: dayStart) else { continue }
                guard !TaskScheduleInterval.hasConcreteTimelineSlot(
                    for: all[index],
                    on: dayStart,
                    calendar: calendar
                ) else { continue }
                guard let anchor = RoutineScheduleAnchorResolver.resolve(
                    for: all[index],
                    on: dayStart,
                    model: model,
                    calendar: calendar
                ) else { continue }

                var task = all[index]
                task.scheduledTime = anchor.start
                task.scheduledEndTime = anchor.end
                ScheduleNormalization.normalizeFields(&task, calendar: calendar)
                task = TaskConstraintAlignment.align(task)
                guard task.scheduledTime != all[index].scheduledTime
                    || task.scheduledEndTime != all[index].scheduledEndTime else { continue }

                task.updatedAt = Date()
                try await taskRepo.update(task)
                all[index] = task
#if DEBUG
                print("[Tasks] assigned routine anchor id=\(task.id.prefix(8)) title=\"\(task.title)\"")
#endif
            }
        }
    }

    /// Marks invalid recurrence rows as superseded instead of deleting user data.
    private func supersedeInvalidScheduledTasks(
        _ ids: [String],
        in allTasks: [LifeTask],
        includingLifeCommitments: Bool = false
    ) async throws {
        for id in ids {
            guard var task = allTasks.first(where: { $0.id == id }) else { continue }
            guard task.status.isActive else { continue }
            if task.isLifeCommitmentTask && !includingLifeCommitments { continue }
            task.status = .superseded
            task.updatedAt = Date()
            try await taskRepo.update(task)
            tasks.removeAll { $0.id == id }
            completedToday.removeAll { $0.id == id }
            print("[Tasks] superseded invalid scheduled task id=\(id.prefix(8))")
        }
    }

    /// After completing one instance, drop other active rows for the same series today.
    private func supersedeDuplicatesAfterCompletion(_ completed: LifeTask, userId: String) async throws {
        guard !userId.isEmpty else { return }
        var all = reloadLocalTasks(for: userId)
        if !all.contains(where: { $0.id == completed.id }) {
            all.append(completed)
        }
        let duplicateIDs = TaskSeriesResolver.staleActiveSeriesIDs(in: all, calendar: .current)
        guard !duplicateIDs.isEmpty else { return }
        try await supersedeInvalidScheduledTasks(
            duplicateIDs,
            in: all,
            includingLifeCommitments: true
        )
    }
    
    /// Persist onboarding starter tasks and refresh the task list.
    public func importOnboardingTasks(_ seedTasks: [LifeTask], userId: String) async {
        guard !userId.isEmpty, !seedTasks.isEmpty else { return }

        await removeOnboardingSeededTasks(userId: userId)
        try? await applyRecurrenceTemplateDedupe(userId: userId)

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

    private func applyRecurrenceTemplateDedupe(userId: String) async throws {
        let all = reloadLocalTasks(for: userId)
        let plan = TaskRecurrenceEngine.dedupeDuplicateRecurrenceTemplates(in: all)
        guard !plan.occurrenceUpdates.isEmpty || !plan.templateIDsToDelete.isEmpty else { return }

        for var occurrence in plan.occurrenceUpdates {
            occurrence.userId = userId
            try await taskRepo.update(occurrence)
            if let index = tasks.firstIndex(where: { $0.id == occurrence.id }) {
                tasks[index] = occurrence
            }
#if DEBUG
            print("[Tasks] re-parented occurrence id=\(occurrence.id.prefix(8)) → template=\(occurrence.parentTaskId?.prefix(8) ?? "?")")
#endif
        }

        for templateID in plan.templateIDsToDelete {
            try await taskRepo.delete(templateID)
            tasks.removeAll { $0.id == templateID }
            completedToday.removeAll { $0.id == templateID }
#if DEBUG
            print("[Tasks] removed duplicate recurrence template id=\(templateID.prefix(8))")
#endif
        }

        applySnapshot(taskRepo.localSnapshot(for: userId), logSource: "recurrence-template-dedupe")
    }

    private struct RecurringCreationPlan {
        var template: LifeTask?
        var occurrence: LifeTask?
        var usesExistingTemplate: Bool
    }

    private func planRecurringCreation(for task: LifeTask, existingTasks: [LifeTask]) -> RecurringCreationPlan {
        let userId = task.userId
        if let existing = TaskRecurrenceEngine.existingRecurrenceTemplate(matching: task, in: existingTasks) {
            let calendar = Calendar.current
            let day = calendar.startOfDay(for: task.scheduledDate ?? Date())
            let shouldCreateToday = existing.recurrenceRule == .none
                || existing.recurrenceOccurs(on: day, calendar: calendar)
            guard shouldCreateToday,
                  !TaskRecurrenceEngine.hasStoredOccurrence(for: existing, on: day, in: existingTasks, calendar: calendar) else {
                return RecurringCreationPlan(template: nil, occurrence: nil, usesExistingTemplate: true)
            }
            var occurrence = TaskRecurrenceEngine.makeOccurrence(from: task, template: existing, scheduledDate: day)
            occurrence.userId = userId
            return RecurringCreationPlan(template: nil, occurrence: occurrence, usesExistingTemplate: true)
        }

        var template = TaskEphemeralityDefaults.enrich(task)
        template.isRecurrenceTemplate = true
        template.scheduledDate = nil
        template.status = .pending
        template.completedAt = nil

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: task.scheduledDate ?? Date())
        let shouldCreateToday = template.recurrenceRule == .none
            || template.recurrenceOccurs(on: day, calendar: calendar)
        guard shouldCreateToday else {
            return RecurringCreationPlan(template: template, occurrence: nil, usesExistingTemplate: false)
        }
        var occurrence = TaskRecurrenceEngine.makeOccurrence(from: task, template: template, scheduledDate: day)
        occurrence.userId = userId
        return RecurringCreationPlan(template: template, occurrence: occurrence, usesExistingTemplate: false)
    }

    private func insertRecurringOccurrenceIfNeeded(_ occurrence: LifeTask) {
        guard !tasks.contains(where: { $0.id == occurrence.id }) else { return }
        tasks.insert(occurrence, at: 0)
        bumpTasksRevision()
        notifyTaskListDidChange()
    }

    private func persistRecurringTask(
        _ task: LifeTask,
        plan: RecurringCreationPlan? = nil,
        decompose: Bool
    ) async {
        let userId = task.userId
        let resolvedPlan = plan ?? planRecurringCreation(for: task, existingTasks: mergedLocalTasks(for: userId))

        if resolvedPlan.usesExistingTemplate {
            guard let occurrence = resolvedPlan.occurrence else { return }
            insertRecurringOccurrenceIfNeeded(occurrence)
            do {
                if reloadLocalTasks(for: userId).contains(where: { $0.id == occurrence.id }) {
                    try await taskRepo.update(occurrence)
                } else {
                    try await taskRepo.create(occurrence)
                }
                if decompose, occurrence.steps.isEmpty {
                    await decomposeTask(occurrence)
                }
            } catch {
                tasks.removeAll { $0.id == occurrence.id }
                self.error = error.localizedDescription
            }
            return
        }

        guard let template = resolvedPlan.template else { return }
        if let occurrence = resolvedPlan.occurrence {
            insertRecurringOccurrenceIfNeeded(occurrence)
        }

        do {
            let stored = reloadLocalTasks(for: userId)
            if !stored.contains(where: { $0.id == template.id }) {
                try await taskRepo.create(template)
            }
            if let occurrence = resolvedPlan.occurrence {
                if stored.contains(where: { $0.id == occurrence.id }) {
                    try await taskRepo.update(occurrence)
                } else {
                    try await taskRepo.create(occurrence)
                }
                if decompose, occurrence.steps.isEmpty {
                    await decomposeTask(occurrence)
                }
            }
        } catch {
            if let occurrence = resolvedPlan.occurrence {
                tasks.removeAll { $0.id == occurrence.id }
            }
            self.error = error.localizedDescription
        }
    }

    /// Create a new task — instant UI update, persistence runs in background.
    public func createTask(_ task: LifeTask) {
        Task { try? await createTaskAndAwait(task) }
    }

    /// Durable create used by planning apply — throws if SQLite/repo write fails.
    public func createTaskAndAwait(_ task: LifeTask) async throws {
        if task.recurrenceRule != .none {
            createRecurringTask(task)
            return
        }
        if MultiDayTaskTags.isMultiDay(task) {
            try await insertTaskWithoutDecomposeAndAwait(task)
            return
        }

        tasks.insert(task, at: 0)
        do {
            var enriched = ScheduleNormalization.normalized(task)
            enriched.semanticProfile = await resolveSemanticProfile(for: enriched)
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = enriched
            }
            try await taskRepo.create(enriched)

            if enriched.steps.isEmpty {
                await decomposeTask(enriched)
            }
            notifyTaskListDidChange()
        } catch {
            tasks.removeAll { $0.id == task.id }
            self.error = error.localizedDescription
            throw error
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
        Task { try? await insertTaskWithoutDecomposeAndAwait(task) }
    }

    private func insertTaskWithoutDecomposeAndAwait(_ task: LifeTask) async throws {
        tasks.insert(task, at: 0)
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
            throw error
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
        let plan = planRecurringCreation(for: task, existingTasks: mergedLocalTasks(for: task.userId))
        if let occurrence = plan.occurrence {
            insertRecurringOccurrenceIfNeeded(occurrence)
        }
        Task {
            await persistRecurringTask(task, plan: plan, decompose: true)
        }
    }
    
    /// Create a task from AI-processed inbox capture.
    public func createFromInbox(_ draft: InboxTaskDraft, userId: String, sourceInboxItemId: String? = nil) async throws -> LifeTask {
        var task = LifeTask(
            title: draft.title,
            lifeArea: draft.lifeArea ?? .personal,
            priority: draft.priority ?? .medium,
            difficulty: draft.difficulty ?? .medium,
            estimatedMinutes: draft.estimatedMinutes,
            sourceInboxItemId: sourceInboxItemId,
            userId: userId
        )
        task.semanticProfile = await resolveSemanticProfile(for: task)
        try await taskRepo.create(task)
        tasks.insert(task, at: 0)
        notifyTaskListDidChange()
        return task
    }

    /// Create a scheduled task from capture routing (events).
    public func createScheduledFromCapture(
        _ draft: InboxTaskDraft,
        scheduledAt: Date,
        userId: String,
        sourceInboxItemId: String? = nil
    ) async throws -> LifeTask {
        var task = LifeTask(
            title: draft.title,
            lifeArea: draft.lifeArea ?? .personal,
            priority: draft.priority ?? .medium,
            difficulty: draft.difficulty ?? .easy,
            estimatedMinutes: draft.estimatedMinutes,
            scheduledDate: Calendar.current.startOfDay(for: scheduledAt),
            scheduledTime: scheduledAt,
            sourceInboxItemId: sourceInboxItemId,
            schedulingMode: .fixedTime,
            timeConstraint: .anchored,
            userId: userId
        )
        task.semanticProfile = await resolveSemanticProfile(for: task)
        try await taskRepo.create(task)
        tasks.insert(task, at: 0)
        notifyTaskListDidChange()
        return task
    }

    /// Update an existing task — optimistic UI, awaits persistence before returning.
    public func updateTask(_ task: LifeTask) {
        Task { await updateTaskAndPersist(task) }
    }

    /// Awaitable update path — use from sheets so dismiss happens after save completes.
    public func updateTaskAndPersist(_ task: LifeTask) async {
        var didPersist = false
        isSuppressingStoreSync = true
        defer {
            isSuppressingStoreSync = false
            if didPersist {
                NotificationCenter.default.post(name: .taskListDidChange, object: nil)
            }
        }

        let materialized = materializeProjectionIfNeeded(task)
        let previous = tasks.first(where: { $0.id == task.id })
            ?? completedToday.first(where: { $0.id == task.id })
        let userId = materialized.userId.isEmpty ? FirebaseManager.shared.resolvedUserId : materialized.userId

        var aligned = TaskConstraintAlignment.align(materialized)
        ScheduleNormalization.normalizeFields(&aligned)
        applyOptimisticUpdate(aligned, replacing: task.id)

        do {
            var enriched = aligned
            let needsSemanticRefresh = previous.map { aligned.semanticFieldsChanged(comparedTo: $0) }
                ?? (aligned.semanticProfile == nil)
            if needsSemanticRefresh {
                let deterministic = TaskSemanticProfileBuilder.build(from: aligned)
                if let existing = aligned.semanticProfile {
                    enriched.semanticProfile = TaskSemanticProfileBuilder.merge(
                        llm: existing,
                        deterministic: deterministic
                    )
                } else {
                    enriched.semanticProfile = deterministic
                }
                enriched = TaskConstraintAlignment.align(enriched)
                applyOptimisticUpdate(enriched, replacing: aligned.id)
            }
            try await taskRepo.update(enriched)
            try await syncRecurrenceEditsToTemplate(enriched)
            if !userId.isEmpty {
                taskStore?.refreshLocal(userId: userId)
                applySnapshot(taskRepo.localSnapshot(for: userId), logSource: "post-edit-local")
            }
            bumpTasksRevision()
            invalidateTimeDisplay(for: enriched.id)
            didPersist = true
            if needsSemanticRefresh {
                enqueueSemanticProfileRefresh(for: enriched)
            }
        } catch {
            revertOptimisticUpdate(saved: materialized, previous: previous, originalID: task.id)
            bumpTasksRevision()
            self.error = error.localizedDescription
        }
    }

    private func applyOptimisticUpdate(_ task: LifeTask, replacing originalID: String) {
        if originalID != task.id {
            tasks.removeAll { $0.id == originalID }
            completedToday.removeAll { $0.id == originalID }
        }
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else if let index = completedToday.firstIndex(where: { $0.id == task.id }) {
            completedToday[index] = task
        } else {
            tasks.insert(task, at: 0)
        }
        bumpTasksRevision()
    }

    private func revertOptimisticUpdate(saved: LifeTask, previous: LifeTask?, originalID: String) {
        guard let previous else {
            tasks.removeAll { $0.id == saved.id || $0.id == originalID }
            completedToday.removeAll { $0.id == saved.id || $0.id == originalID }
            return
        }
        tasks.removeAll { $0.id == saved.id && saved.id != previous.id }
        completedToday.removeAll { $0.id == saved.id && saved.id != previous.id }
        if let index = tasks.firstIndex(where: { $0.id == previous.id }) {
            tasks[index] = previous
        } else if let index = completedToday.firstIndex(where: { $0.id == previous.id }) {
            completedToday[index] = previous
        } else if previous.status.isActive {
            tasks.insert(previous, at: 0)
        } else {
            completedToday.insert(previous, at: 0)
        }
    }

    /// Timeline projections use stable ids — convert to a real row before persisting edits.
    private func materializeProjectionIfNeeded(_ task: LifeTask) -> LifeTask {
        guard task.id.hasPrefix("proj-") else { return task }
        var materialized = task
        materialized.id = UUID().uuidString
        materialized.updatedAt = Date()
        return materialized
    }

    /// Persists EventKit identifiers returned from calendar sync.
    public func applyCalendarEventIdentifiers(_ updates: [LifeTask]) async {
        guard !updates.isEmpty else { return }
        for update in updates {
            if let index = tasks.firstIndex(where: { $0.id == update.id }) {
                guard tasks[index].calendarEventIdentifier != update.calendarEventIdentifier else { continue }
                tasks[index].calendarEventIdentifier = update.calendarEventIdentifier
                do {
                    try await taskRepo.update(tasks[index])
                } catch {
                    self.error = error.localizedDescription
                }
                continue
            }
            if let index = completedToday.firstIndex(where: { $0.id == update.id }) {
                completedToday[index].calendarEventIdentifier = update.calendarEventIdentifier
                do {
                    try await taskRepo.update(completedToday[index])
                } catch {
                    self.error = error.localizedDescription
                }
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

        let userId = task.userId.isEmpty ? FirebaseManager.shared.resolvedUserId : task.userId
        await scheduleMutation.persist(updated, userId: userId, reconcileSchedule: true)
        return updated.scheduledTime
    }

    /// Recurrence fields to show when editing an occurrence — reads from the series template.
    public func recurrenceFieldsForEditing(_ task: LifeTask) -> (recurrence: TaskRecurrence, weekdays: [Int]) {
        let source = TaskRecurrenceEngine.recurrenceSource(for: task, in: schedulingContext)
        return (source.recurrenceRule, source.recurrenceWeekdaysValue)
    }

    /// Keep recurrence templates aligned when an occurrence or legacy task is edited.
    private func syncRecurrenceEditsToTemplate(_ task: LifeTask) async throws {
        let userId = task.userId.isEmpty ? FirebaseManager.shared.resolvedUserId : task.userId
        let localTasks = userId.isEmpty ? schedulingContext : taskRepo.localAllTasks(for: userId)

        if let parentId = task.parentTaskId {
            var template = recurrenceTemplates.first(where: { $0.id == parentId })
                ?? localTasks.first(where: { $0.id == parentId })
            guard var template else { return }

            if task.recurrenceRule != .none {
                template.recurrence = task.recurrence
                template.recurrenceInterval = task.recurrenceInterval
                template.recurrenceWeekdays = task.recurrenceWeekdays
            }
            template.title = task.title
            template.description = task.description
            template.lifeArea = task.lifeArea
            template.priority = task.priority
            template.difficulty = task.difficulty
            template.estimatedMinutes = task.estimatedMinutes
            template.requiredEnergy = task.requiredEnergy
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
        
        let hasConfiguredKey = GLMService.shared.hasConfiguredAPIKey
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

    /// Semantic understanding — LLM when available, deterministic safety merge always.
    private func resolveSemanticProfile(for task: LifeTask) async -> TaskSemanticProfile {
        let deterministic = TaskSemanticProfileBuilder.build(from: task)
        let hasAIKey = GLMService.shared.hasConfiguredAPIKey
        guard hasAIKey else { return deterministic }

        enum RaceResult {
            case profile(TaskSemanticProfile)
            case finishedWithoutProfile
        }

        let result = await withTaskGroup(of: RaceResult.self) { group in
            group.addTask { [semanticAnalyzer] in
                if let llm = try? await semanticAnalyzer.analyze(task: task) {
                    return .profile(llm)
                }
                return .finishedWithoutProfile
            }
            group.addTask {
                try? await Task.sleep(
                    nanoseconds: UInt64(Self.semanticAnalysisTimeoutSeconds * 1_000_000_000)
                )
                return .finishedWithoutProfile
            }
            defer { group.cancelAll() }
            return await group.next() ?? .finishedWithoutProfile
        }

        if case .profile(let llm) = result {
            return TaskSemanticProfileBuilder.merge(llm: llm, deterministic: deterministic)
        }
        return deterministic
    }

    /// Refreshes LLM semantics after a fast local save — never blocks edit sheets.
    private func enqueueSemanticProfileRefresh(for task: LifeTask) {
        let snapshotTitle = task.title
        let snapshotID = task.id
        let userId = task.userId.isEmpty ? FirebaseManager.shared.resolvedUserId : task.userId

        Task { [weak self] in
            guard let self else { return }
            let profile = await self.resolveSemanticProfile(for: task)
            guard var current = self.tasks.first(where: { $0.id == snapshotID })
                ?? self.completedToday.first(where: { $0.id == snapshotID }) else { return }
            guard current.title == snapshotTitle else { return }

            current.semanticProfile = profile
            current = TaskConstraintAlignment.align(current)
            do {
                try await self.taskRepo.update(current)
                self.applyOptimisticUpdate(current, replacing: snapshotID)
                if !userId.isEmpty {
                    self.taskStore?.refreshLocal(userId: userId)
                }
                self.bumpTasksRevision()
            } catch {
#if DEBUG
                print("[Tasks] background semantic refresh failed id=\(snapshotID.prefix(8)): \(error.localizedDescription)")
#endif
            }
        }
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
        let useAI = TaskManagementPreferences.smarterFocusTipsEnabled

        for task in tasks {
            let fingerprint = TimeDisplayFingerprint(task: task, context: context)
            let local = localTimeDisplay(for: task, context: context)

            if !useAI {
                taskTimeDisplays[task.id] = local
                timeDisplayFingerprints[task.id] = fingerprint
                continue
            }

            if let cached = taskTimeDisplays[task.id],
               timeDisplayFingerprints[task.id] == fingerprint,
               !cached.needsAIRefinement {
                continue
            }

            taskTimeDisplays[task.id] = local
            timeDisplayFingerprints[task.id] = fingerprint

            guard TaskFocusStretchResolver.displayInfo(for: task, context: context).needsAIRefinement else {
                continue
            }

            loadingTimeDisplayTaskIds.insert(task.id)
            defer { loadingTimeDisplayTaskIds.remove(task.id) }

            if let refined = await focusStretchRefiner.refine(
                task: task,
                context: context,
                estimatedMinutes: task.estimatedMinutes
            ) {
                taskTimeDisplays[task.id] = refined
                timeDisplayFingerprints[task.id] = fingerprint
            }
        }
    }

    public func invalidateTimeDisplay(for taskId: String) {
        taskTimeDisplays.removeValue(forKey: taskId)
        timeDisplayFingerprints.removeValue(forKey: taskId)
    }

    private func localTimeDisplay(
        for task: LifeTask,
        context: TaskFocusStretchResolver.Context
    ) -> TaskTimeDisplayInfo {
        let info = TaskFocusStretchResolver.displayInfo(for: task, context: context)
        return TaskTimeDisplayInfo(
            lineLabel: info.lineLabel,
            chipLabel: info.chipLabel,
            usesFocusStretch: info.usesFocusStretch,
            focusStretchMinutes: info.focusStretchMinutes,
            needsAIRefinement: false
        )
    }

    private struct TimeDisplayFingerprint: Equatable {
        let estimatedMinutes: Int
        let difficulty: TaskDifficulty
        let energyBucket: Int

        init(task: LifeTask, context: TaskFocusStretchResolver.Context) {
            estimatedMinutes = task.estimatedMinutes
            difficulty = task.difficulty
            energyBucket = Int(context.energyScore * 100)
        }
    }

    public func isLoadingTimeDisplay(taskId: String) -> Bool {
        loadingTimeDisplayTaskIds.contains(taskId)
    }
    
    /// Resolves a timeline task id from active lists, storage, or today's in-memory projections.
    public func resolveTimelineTask(
        id: String,
        titleHint: String? = nil,
        referenceDate: Date = Date()
    ) -> LifeTask? {
        if let task = tasks.first(where: { $0.id == id }) { return task }
        if let task = completedToday.first(where: { $0.id == id }) { return task }
        let all = schedulingContext
        if let task = all.first(where: { $0.id == id }) { return task }

        let calendar = Calendar.current
        let day = calendar.startOfDay(for: referenceDate)
        let projected = TaskRecurrenceEngine.timelineProjections(for: all, on: day, calendar: calendar)
        if let match = projected.first(where: { $0.id == id }) {
            return match
        }

        if let titleHint,
           !titleHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return projected.first {
                $0.title.caseInsensitiveCompare(titleHint) == .orderedSame
            } ?? all.first {
                $0.status.isActive && $0.title.caseInsensitiveCompare(titleHint) == .orderedSame
            }
        }

        return nil
    }

    /// Persists a projected occurrence or reactivates a superseded row for the same template/day.
    public func materializeTimelineTask(_ task: LifeTask, userId: String) async throws -> LifeTask {
        var all = try await taskRepo.getAll(for: userId)
        let calendar = Calendar.current
        let day = task.scheduledDate.map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: Date())
        let seriesKey = TaskScheduleQuery.seriesKey(for: task)
        if let existing = all.first(where: { candidate in
            guard candidate.id != task.id, candidate.status.isActive else { return false }
            guard TaskScheduleQuery.seriesKey(for: candidate) == seriesKey else { return false }
            if let scheduled = candidate.scheduledDate {
                return calendar.isDate(scheduled, inSameDayAs: day)
            }
            return true
        }) {
            return existing
        }

        if let stored = all.first(where: { $0.id == task.id }) {
            if stored.status.isActive { return stored }
            if stored.status == .superseded {
                var reactivated = stored
                reactivated.status = .pending
                reactivated.updatedAt = Date()
                try await taskRepo.update(reactivated)
                print("[Tasks] reactivated materialized projection id=\(reactivated.id.prefix(8))")
                return reactivated
            }
            return stored
        }

        if let parentId = task.parentTaskId,
           let scheduledDay = task.scheduledDate,
           var stale = all.first(where: { candidate in
               candidate.parentTaskId == parentId
                   && candidate.status == .superseded
                   && candidate.scheduledDate.map { calendar.isDate($0, inSameDayAs: scheduledDay) } == true
           }) {
            stale.status = .pending
            stale.updatedAt = Date()
            try await taskRepo.update(stale)
            print("[Tasks] reactivated superseded for timeline complete id=\(stale.id.prefix(8))")
            return stale
        }

        var occurrence = task
        occurrence.userId = userId
        occurrence.status = .pending
        try await taskRepo.create(occurrence)
        print("[Tasks] materialized timeline projection id=\(occurrence.id.prefix(8)) title=\"\(occurrence.title)\"")
        return occurrence
    }

    /// Complete a task tapped on the live timeline — materializes projections first when needed.
    @discardableResult
    public func completeTimelineTask(id: String, userId: String, titleHint: String? = nil) async -> TaskUndoAction? {
        guard !userId.isEmpty else { return nil }
        guard var task = resolveTimelineTask(id: id, titleHint: titleHint) else {
            return nil
        }

        let needsMaterialize = !schedulingContext.contains(where: { $0.id == task.id && $0.status.isActive })
        if needsMaterialize {
            do {
                task = try await materializeTimelineTask(task, userId: userId)
                refreshFromLocal(userId: userId)
            } catch {
                self.error = error.localizedDescription
                return nil
            }
        }

        guard task.status.isActive else {
            return nil
        }

        return await completeTask(task)
    }

    /// Mark a timeline task incomplete — resolves from completedToday or storage.
    @discardableResult
    public func uncompleteTimelineTask(id: String, userId: String, titleHint: String? = nil) async -> Bool {
        guard !userId.isEmpty else { return false }

        if let task = completedToday.first(where: { $0.id == id }) {
            await markIncomplete(task)
            return true
        }

        if let titleHint,
           !titleHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let task = completedToday.first(where: { $0.title.caseInsensitiveCompare(titleHint) == .orderedSame }) {
            await markIncomplete(task)
            return true
        }

        if let task = resolveTimelineTask(id: id, titleHint: titleHint), task.status == .completed {
            await markIncomplete(task)
            return true
        }

        return false
    }

    /// Mark a task as completed and schedule the next recurring occurrence when applicable.
    @discardableResult
    public func completeTask(_ task: LifeTask) async -> TaskUndoAction? {
        let activeIndex = tasks.firstIndex(where: { $0.id == task.id })
        let restoredSnapshot = task

        var updated = task
        updated.status = .completed
        updated.completedAt = Date()
        ScheduleNormalization.normalizeFields(&updated)

        // Optimistic UI — lists update immediately before persistence.
        tasks.removeAll { $0.id == task.id }
        completedToday.insert(updated, at: 0)

        do {
            try await taskRepo.update(updated)

            let userId = updated.userId.isEmpty ? task.userId : updated.userId
            if !userId.isEmpty {
                try await supersedeDuplicatesAfterCompletion(updated, userId: userId)
                refreshFromLocal(userId: userId)
            }

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
            notifyTaskListDidChange()
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

    /// Request full day replan on the next reconcile (e.g. after AI schedule mutations).
    public func requestForceReplan() {
        pendingForceReplan = true
    }

    /// Repairs midnight placeholder schedules after load/sync — today and tomorrow.
    private func repairMidnightSchedulesOnLoad(userId: String) async {
        guard !userId.isEmpty else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        await repairMidnightPlaceholderSchedules(for: today, userId: userId, model: LifeModelStore.load(), calendar: calendar)
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) {
            await repairMidnightPlaceholderSchedules(for: tomorrow, userId: userId, model: LifeModelStore.load(), calendar: calendar)
        }
    }

    /// Repairs same-day schedule overlaps and snaps life commitments to LifeModel block times.
    public func reconcileTodaySchedule(
        userId: String,
        model: LifeModel? = LifeModelStore.load(),
        date: Date = Date(),
        calendar: Calendar = .current,
        postScheduleNotification: Bool = false,
        deferSnapshot: Bool = false
    ) async {
        guard !userId.isEmpty else { return }
        if isReconciling {
            pendingReconcileAfterCurrent = true
            return
        }
        let managesStoreSync = !isSuppressingStoreSync
        isReconciling = true
        if managesStoreSync {
            isSuppressingStoreSync = true
        }
        defer {
            isReconciling = false
            if managesStoreSync {
                isSuppressingStoreSync = false
            }
            if pendingReconcileAfterCurrent {
                pendingReconcileAfterCurrent = false
                Task { [weak self] in
                    guard let self else { return }
                    await self.reconcileTodaySchedule(
                        userId: userId,
                        model: model,
                        date: date,
                        calendar: calendar,
                        postScheduleNotification: postScheduleNotification,
                        deferSnapshot: deferSnapshot
                    )
                }
            }
        }

        await migrateConstraintFieldsIfNeeded(userId: userId)
        applySnapshot(taskRepo.localSnapshot(for: userId), logSource: "pre-reconcile-local", authoritative: true)
        await normalizeMidnightSentinelsInStorage(userId: userId)

        let structure = DayStructureCompiler.compile(model: model)
        tasks = DayStructureCompiler.backfillAnchorIDs(tasks: tasks, structure: structure, calendar: calendar)

        await sweepPreviousDayIfNeeded(userId: userId, now: date, calendar: calendar)

        let day = calendar.startOfDay(for: date)
        var allChangedIDs = Set<String>()

        await repairMidnightPlaceholderSchedules(for: day, userId: userId, model: model, calendar: calendar)
        await correctRoutineScheduleDrift(
            for: day,
            userId: userId,
            model: model,
            calendar: calendar,
            batchNotifications: true
        )

        await assignUnslottedFlexibleTasks(
            for: day,
            model: model,
            calendar: calendar,
            batchNotifications: true,
            userId: userId
        )

        let needsFullReplan = ReconcilePolicy.needsFullReplan(
            ReconcilePolicy.Input(
                tasks: tasks + completedToday,
                day: day,
                model: model,
                forceReplan: pendingForceReplan
            ),
            calendar: calendar
        )
        pendingForceReplan = false

        if SchedulePlannerFlags.useUnifiedDayPlanner, needsFullReplan {
            let plan = DaySchedulePlanner.plan(
                tasks: tasks + completedToday,
                on: day,
                model: model,
                structure: structure,
                now: date,
                calendar: calendar
            )
            let applied = DaySchedulePlanner.apply(plan: plan, to: tasks, on: day, calendar: calendar)
            for var task in applied.tasks where applied.changedIDs.contains(task.id) {
                if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[index] = task
                }
                do {
                    try await taskRepo.update(task)
                    allChangedIDs.insert(task.id)
                } catch {
                    self.error = error.localizedDescription
                }
            }
        } else {
            let activePool = TaskScheduleQuery.scheduledActiveTasks(from: tasks, on: day, calendar: calendar)

            if !activePool.isEmpty {
                let syncedPool = activePool.map {
                    DayScheduleReconciler.syncCommitmentTimes($0, model: model, day: day, calendar: calendar)
                }
                let commitmentDrift = zip(activePool, syncedPool).contains { original, synced in
                    original.scheduledTime != synced.scheduledTime
                        || original.scheduledEndTime != synced.scheduledEndTime
                        || original.estimatedMinutes != synced.estimatedMinutes
                }

                if commitmentDrift || DayScheduleReconciler.hasOverlap(syncedPool, on: day, calendar: calendar) {
                    let result = DayScheduleReconciler.reconcile(
                        tasks: activePool,
                        on: day,
                        model: model,
                        calendar: calendar
                    )
                    for updated in result.tasks where result.changedTaskIDs.contains(updated.id) {
                        if let index = tasks.firstIndex(where: { $0.id == updated.id }) {
                            tasks[index] = updated
                        }
                        if let index = completedToday.firstIndex(where: { $0.id == updated.id }) {
                            completedToday[index] = updated
                        }
                        do {
                            try await taskRepo.update(updated)
                            allChangedIDs.insert(updated.id)
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
            }
        }

        let overlapFixed = await resolveOverlapsIfNeeded(
            for: day,
            userId: userId,
            model: model,
            now: date,
            calendar: calendar
        )
        allChangedIDs.formUnion(overlapFixed)

        let staleFixed = await supersedeSeriesDuplicatesAfterReconcile(userId: userId, day: day, calendar: calendar)
        allChangedIDs.formUnion(staleFixed)

        taskStore?.refreshLocal(userId: userId)
        if !deferSnapshot {
            applySnapshot(taskRepo.localSnapshot(for: userId), logSource: "post-reconcile", authoritative: true)
        }

        publishDayScheduleSnapshot(day: day, changedIDs: allChangedIDs, calendar: calendar)
        bumpTasksRevision()

        if postScheduleNotification || !allChangedIDs.isEmpty {
            notifyScheduleDidChange()
        }
    }

    /// Mandatory overlap repair — runs after planner/legacy branches regardless of ReconcilePolicy.
    private func resolveOverlapsIfNeeded(
        for day: Date,
        userId: String,
        model: LifeModel?,
        now: Date,
        calendar: Calendar
    ) async -> Set<String> {
        let allLocal = taskRepo.localAllTasks(for: userId)
        var pool = TaskScheduleQuery.scheduledActiveTasks(from: allLocal, on: day, calendar: calendar)
        guard pool.count > 1 else { return [] }
        guard DayScheduleReconciler.hasOverlap(pool, on: day, calendar: calendar) else { return [] }

        // System repair: meals overlapping anchored blocks must shift — clear stale user-placed locks.
        var preparedPool = pool
        for index in preparedPool.indices {
            var task = preparedPool[index]
            guard OnboardingTaskSeeder.isMealRoutineTitle(task.title) else { continue }
            task = TaskConstraintAlignment.align(task)
            if task.timeConstraintValue == .anchored {
                task.applyTimeConstraint(.flexible)
            }
            if task.userPlacedScheduleAt != nil {
                task.userPlacedScheduleAt = nil
            }
            preparedPool[index] = task
        }
        pool = preparedPool

#if DEBUG
        print("[Tasks] overlap repair pool=\(pool.map { $0.title }.joined(separator: ", "))")
#endif

        let result = DayScheduleReconciler.reconcile(
            tasks: pool,
            on: day,
            model: model,
            now: now,
            calendar: calendar
        )
        var changedIDs = Set<String>()
        for updated in result.tasks where result.changedTaskIDs.contains(updated.id) {
            var aligned = TaskConstraintAlignment.align(updated)
            aligned.updatedAt = Date()
            do {
                try await taskRepo.update(aligned)
                changedIDs.insert(aligned.id)
            } catch {
                self.error = error.localizedDescription
            }
        }
#if DEBUG
        if !changedIDs.isEmpty {
            print("[Tasks] overlap repair changed ids=\(changedIDs.map { $0.prefix(8) }.joined(separator: ","))")
        }
#endif
        return changedIDs
    }

    /// Supersede duplicate active rows for the same series after schedule repair.
    private func supersedeSeriesDuplicatesAfterReconcile(
        userId: String,
        day: Date,
        calendar: Calendar
    ) async -> Set<String> {
        guard !userId.isEmpty else { return [] }
        let all = reloadLocalTasks(for: userId)
        let staleIDs = TaskSeriesResolver.staleActiveSeriesIDs(in: all, on: day, calendar: calendar)
        guard !staleIDs.isEmpty else { return [] }
        do {
            try await supersedeInvalidScheduledTasks(
                staleIDs,
                in: all,
                includingLifeCommitments: true
            )
            return Set(staleIDs)
        } catch {
            self.error = error.localizedDescription
            return []
        }
    }

    /// Snaps mis-slotted routines (midnight sentinel or date-only) back to canonical anchors.
    private func repairMidnightPlaceholderSchedules(
        for day: Date,
        userId: String,
        model: LifeModel?,
        calendar: Calendar
    ) async {
        let profile = UserLifeProfileStore.load()
        let candidates = taskRepo.localAllTasks(for: userId).filter { task in
            needsRoutineAnchorRepair(task, on: day, calendar: calendar)
        }
        guard !candidates.isEmpty else { return }

        for task in candidates {
            await applyRoutineAnchorRepair(task, on: day, userId: userId, model: model, profile: profile, calendar: calendar)
        }
    }

    private func needsRoutineAnchorRepair(
        _ task: LifeTask,
        on day: Date,
        calendar: Calendar
    ) -> Bool {
        guard task.status.isActive,
              let scheduledDate = task.scheduledDate,
              calendar.isDate(scheduledDate, inSameDayAs: day) else { return false }
        if TaskScheduleInterval.isPlaceholderMidnightSchedule(for: task, calendar: calendar) {
            return true
        }
        guard TaskScheduleInterval.hasNoClockTime(task),
              OnboardingTaskSeeder.isKnownDailyRoutineTitle(task.title) else { return false }
        return !TaskScheduleInterval.hasConcreteTimelineSlot(for: task, on: day, calendar: calendar)
    }

    private func applyRoutineAnchorRepair(
        _ task: LifeTask,
        on day: Date,
        userId: String,
        model: LifeModel?,
        profile: UserLifeProfile,
        calendar: Calendar
    ) async {
        if let anchor = RoutineScheduleAnchorResolver.resolve(
            for: task,
            on: day,
            model: model,
            profile: profile,
            calendar: calendar
        ) {
            if OnboardingTaskSeeder.isMealRoutineTitle(task.title) {
                let allLocal = taskRepo.localAllTasks(for: userId)
                let proposed = TaskScheduleInterval(taskID: task.id, start: anchor.start, end: anchor.end)
                let blockers = TaskScheduleQuery.scheduledActiveTasks(from: allLocal, on: day, calendar: calendar)
                    .filter { $0.id != task.id && ($0.isLifeCommitmentTask || $0.timeConstraintValue == .anchored) }
                if TaskScheduleInterval.intervals(from: blockers, on: day, calendar: calendar)
                    .contains(where: { proposed.overlaps($0) }) {
                    var cleared = task
                    cleared.scheduledTime = nil
                    cleared.scheduledEndTime = nil
                    cleared = TaskConstraintAlignment.align(cleared)
                    cleared.updatedAt = Date()
                    if let index = tasks.firstIndex(where: { $0.id == cleared.id }) {
                        tasks[index] = cleared
                    }
                    do {
                        try await taskRepo.update(cleared)
                    } catch {
                        self.error = error.localizedDescription
                    }
                    return
                }
            }
            var updated = task
            updated.scheduledDate = day
            updated.scheduledTime = anchor.start
            updated.scheduledEndTime = anchor.end
            if anchor.treatAsFixed || task.isLifeCommitmentTask {
                updated.schedulingMode = .fixedTime
            }
            updated = TaskConstraintAlignment.align(updated)
            updated.updatedAt = Date()
            if let index = tasks.firstIndex(where: { $0.id == updated.id }) {
                tasks[index] = updated
            }
            do {
                try await taskRepo.update(updated)
            } catch {
                self.error = error.localizedDescription
            }
            return
        }

        var cleared = task
        cleared.scheduledTime = nil
        cleared.scheduledEndTime = nil
        cleared.updatedAt = Date()
        if let index = tasks.firstIndex(where: { $0.id == cleared.id }) {
            tasks[index] = cleared
        }
        do {
            try await taskRepo.update(cleared)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Snaps mis-slotted routines (e.g. Dinner at noon) back to canonical anchors.
    private func correctRoutineScheduleDrift(
        for day: Date,
        userId: String,
        model: LifeModel?,
        calendar: Calendar,
        batchNotifications: Bool = false
    ) async {
        let profile = UserLifeProfileStore.load()
        let allLocal = taskRepo.localAllTasks(for: userId)
        let candidates = allLocal.filter { task in
            guard task.status.isActive, let scheduledDate = task.scheduledDate,
                  calendar.isDate(scheduledDate, inSameDayAs: day) else { return false }
            if TaskScheduleInterval.isPlaceholderMidnightSchedule(for: task, calendar: calendar) {
                return true
            }
            let title = task.title.lowercased()
            if task.tags.contains("daily-routine")
                || task.tags.contains("fixed")
                || TaskEphemeralityDefaults.boundingBox(for: task) != nil
                || title.contains("commute")
                || title.contains("standup")
                || title.contains("stand-up")
                || (title.contains("office") && title.contains("work")) {
                return true
            }
            return RoutineScheduleAnchorResolver.resolve(
                for: task,
                on: day,
                model: model,
                profile: profile,
                calendar: calendar
            )?.treatAsFixed == true
        }

        var didChange = false
        for task in candidates {
            guard let anchor = RoutineScheduleAnchorResolver.resolve(
                for: task,
                on: day,
                model: model,
                profile: profile,
                calendar: calendar
            ) else { continue }
            guard RoutineScheduleAnchorResolver.shouldRestore(task: task, anchor: anchor, calendar: calendar) else {
                continue
            }
            if OnboardingTaskSeeder.isMealRoutineTitle(task.title) {
                let proposed = TaskScheduleInterval(taskID: task.id, start: anchor.start, end: anchor.end)
                let blockers = TaskScheduleQuery.scheduledActiveTasks(from: allLocal, on: day, calendar: calendar)
                    .filter { $0.id != task.id && ($0.isLifeCommitmentTask || $0.timeConstraintValue == .anchored) }
                if TaskScheduleInterval.intervals(from: blockers, on: day, calendar: calendar)
                    .contains(where: { proposed.overlaps($0) }) {
                    continue
                }
            }
            var updated = task
            updated.scheduledDate = day
            updated.scheduledTime = anchor.start
            updated.scheduledEndTime = anchor.end
            if task.isLifeCommitmentTask || (anchor.treatAsFixed && !OnboardingTaskSeeder.isMealRoutineTitle(task.title)) {
                updated.schedulingMode = .fixedTime
                updated.applyTimeConstraint(.anchored)
            } else if task.tags.contains("daily-routine") || OnboardingTaskSeeder.isMealRoutineTitle(task.title) {
                updated.schedulingMode = .fixedTime
                updated.applyTimeConstraint(.flexible)
            } else if anchor.treatAsFixed || task.tags.contains("fixed") {
                updated.schedulingMode = .fixedTime
                updated.applyTimeConstraint(.anchored)
            }
            updated.updatedAt = Date()
            if let index = tasks.firstIndex(where: { $0.id == updated.id }) {
                tasks[index] = updated
            }
            do {
                try await taskRepo.update(updated)
                didChange = true
            } catch {
                self.error = error.localizedDescription
            }
        }
        if didChange, !batchNotifications {
            notifyScheduleDidChange()
        }
    }

    /// Places flexible tasks that lack a clock time into the next open slots today.
    private func assignUnslottedFlexibleTasks(
        for day: Date,
        model: LifeModel?,
        calendar: Calendar,
        batchNotifications: Bool = false,
        userId: String = ""
    ) async {
        let isToday = calendar.isDateInToday(day)
        let profile = UserLifeProfileStore.load()
        let unslotted = tasks.filter { task in
            guard task.status.isActive, task.isSchedulerMovable else { return false }
            if TaskScheduleInterval.hasConcreteTimelineSlot(for: task, on: day, calendar: calendar) {
                return false
            }
            if task.tags.contains("daily-routine") || task.tags.contains("fixed") {
                return false
            }
            if TaskScheduleInterval.isFlexibleDaySchedule(for: task, on: day, calendar: calendar) {
                return true
            }
            guard task.scheduledTime == nil else { return false }
            if let scheduledDate = task.scheduledDate {
                return calendar.isDate(scheduledDate, inSameDayAs: day)
            }
            return isToday
        }
        guard !unslotted.isEmpty else { return }

        var anchored: [LifeTask] = []
        var toAllocate: [LifeTask] = []
        for task in unslotted {
            if let anchor = RoutineScheduleAnchorResolver.resolve(
                for: task,
                on: day,
                model: model,
                profile: profile,
                calendar: calendar
            ), anchor.treatAsFixed {
                anchored.append(task)
            } else {
                toAllocate.append(task)
            }
        }

        for task in anchored {
            guard let anchor = RoutineScheduleAnchorResolver.resolve(
                for: task,
                on: day,
                model: model,
                profile: profile,
                calendar: calendar
            ) else { continue }
            let proposed = TaskScheduleInterval(
                taskID: task.id,
                start: anchor.start,
                end: anchor.end
            )
            let existingIntervals = TaskScheduleInterval.intervals(
                from: tasks.filter { $0.status.isActive && $0.id != task.id },
                on: day,
                calendar: calendar
            )
            if existingIntervals.contains(where: { proposed.overlaps($0) }) {
                continue
            }
            var updated = task
            updated.scheduledDate = day
            updated.scheduledTime = anchor.start
            updated.scheduledEndTime = anchor.end
            updated.schedulingMode = .fixedTime
            updated = TaskConstraintAlignment.align(updated)
            updated.updatedAt = Date()
            if let index = tasks.firstIndex(where: { $0.id == updated.id }) {
                tasks[index] = updated
            }
            do {
                try await taskRepo.update(updated)
            } catch {
                self.error = error.localizedDescription
            }
        }

        let requests = toAllocate.map { task in
            DaySlotAllocator.Request(
                id: task.id,
                estimatedMinutes: max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes),
                priority: task.priority,
                preferredStart: RoutineScheduleAnchorResolver.preferredStart(
                    for: task,
                    on: day,
                    model: model,
                    profile: profile,
                    calendar: calendar
                )
            )
        }
        let taskByID = Dictionary.uniquingFirstValue(toAllocate.map { ($0.id, $0) })
        var occupied = tasks.filter { task in
            guard task.status.isActive, let scheduledDate = task.scheduledDate, task.scheduledTime != nil else {
                return false
            }
            return calendar.isDate(scheduledDate, inSameDayAs: day)
        }

        var remainingToAllocate = toAllocate
        if !toAllocate.isEmpty {
            let healthContext = userId.isEmpty
                ? nil
                : BackgroundAnalyticsService.shared.cachedAIContext(userId: userId)?.promptBlock
            let context = AIScheduleSlotService.DayContext(
                day: day,
                allTasks: tasks,
                unslotted: toAllocate,
                model: model,
                healthContext: healthContext
            )
            let suggestions = await AIScheduleSlotService.suggestSlots(for: context)
            if !suggestions.isEmpty {
                var working = tasks
                let changed = AIScheduleSlotService.applySuggestions(suggestions, to: &working, on: day, calendar: calendar)
                var aiBatch: [LifeTask] = []
                for taskID in changed {
                    guard let updated = working.first(where: { $0.id == taskID }) else { continue }
                    if let index = tasks.firstIndex(where: { $0.id == taskID }) {
                        tasks[index] = updated
                    }
                    occupied.append(updated)
                    aiBatch.append(updated)
                }
                if !aiBatch.isEmpty {
                    do {
                        try await taskRepo.updateMany(aiBatch)
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                let assignedIDs = Set(suggestions.map(\.id))
                remainingToAllocate = toAllocate.filter { !assignedIDs.contains($0.id) }
            }
        }

        var allocations: [DaySlotAllocator.Allocation] = []
        for request in requests.filter({ req in remainingToAllocate.contains(where: { $0.id == req.id }) }).sorted(by: { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            switch (lhs.preferredStart, rhs.preferredStart) {
            case let (left?, right?): return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.id < rhs.id
            }
        }) {
            guard let task = taskByID[request.id] else { continue }
            let kind = SchedulingWindowSelector.windowKind(
                for: task.lifeArea,
                semanticType: task.semanticProfile?.semanticType
            )
            let workHours = SchedulingWindowSelector.workHours(
                for: kind,
                profile: profile,
                lifeModel: model
            )
            guard let allocation = DaySlotAllocator.allocate(
                requests: [request],
                existingTasks: occupied,
                workHours: workHours,
                referenceDay: day,
                calendar: calendar
            ).first else { continue }

            allocations.append(allocation)
            var placeholder = task
            placeholder.scheduledDate = day
            placeholder.scheduledTime = allocation.scheduledTime
            occupied.append(placeholder)
        }

        let allocationByID = Dictionary.uniquingFirstValue(allocations.map { ($0.id, $0.scheduledTime) })
        var slotBatch: [LifeTask] = []
        for task in remainingToAllocate {
            guard let slot = allocationByID[task.id] else { continue }
            var updated = task
            updated.scheduledDate = day
            updated.scheduledTime = slot
            let duration = max(updated.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
            updated.scheduledEndTime = slot.addingTimeInterval(TimeInterval(duration * 60))
            updated.updatedAt = Date()
            if let index = tasks.firstIndex(where: { $0.id == updated.id }) {
                tasks[index] = updated
            }
            slotBatch.append(updated)
        }
        if !slotBatch.isEmpty {
            do {
                try await taskRepo.updateMany(slotBatch)
            } catch {
                self.error = error.localizedDescription
            }
        }
        if !anchored.isEmpty || !allocations.isEmpty {
            if !batchNotifications {
                notifyScheduleDidChange()
            }
        }
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
        var batch: [LifeTask] = []
        batch.reserveCapacity(result.changedTaskIDs.count)
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
            batch.append(updated)
        }
        if !batch.isEmpty {
            do {
                try await taskRepo.updateMany(batch)
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
        existingTasks: [LifeTask]? = nil,
        calendar: Calendar = .current
    ) async {
        guard !userId.isEmpty else { return }

        let all: [LifeTask]
        if let existingTasks {
            all = existingTasks
        } else {
            do {
                all = try await taskRepo.getAll(for: userId)
            } catch {
                self.error = error.localizedDescription
                return
            }
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
            guard task.schedulingMode != .fixedTime || task.timeConstraint != .anchored else { continue }
            task.schedulingMode = .fixedTime
            task.applyTimeConstraint(.anchored)
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

        try? await applyRecurrenceTemplateDedupe(userId: userId)

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
            unprocessedCount = items.filter { $0.status == .unprocessed || $0.status == .needsReview }.count
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// Route capture through unified CaptureRouter (auto-process).
    public func routeCapture(_ request: CaptureRequest, userId: String) async -> CaptureRouteResult {
        isProcessing = true
        defer { isProcessing = false }

        if CaptureOfflineQueue.shared.shouldDeferRouting {
            CaptureOfflineQueue.shared.enqueue(request, userId: userId)
            let preview = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return CaptureRouteResult(outcome: .queuedOffline(preview: preview))
        }

        let result = await CaptureRouter.shared.route(request, userId: userId)
        await loadItems(userId: userId)
        return result
    }

    /// Process captures queued while offline.
    public func processOfflineCaptureQueue(userId: String) async {
        let results = await CaptureOfflineQueue.shared.processPending(userId: userId) { request, uid in
            await CaptureRouter.shared.route(request, userId: uid)
        }
        if !results.isEmpty {
            await loadItems(userId: userId)
        }
        for result in results {
            NotificationCenter.default.post(
                name: .captureDidRoute,
                object: nil,
                userInfo: [CaptureNotificationKey.result: CaptureRouteResultBox(result)]
            )
        }
    }

    /// Quick capture — routes via CaptureRouter (same as composer).
    public func quickCapture(text: String, userId: String, source: CaptureSource = .inbox) async -> CaptureRouteResult {
        await routeCapture(
            CaptureRequest(text: text, source: source, contextHints: CaptureContextHints(screen: "inbox")),
            userId: userId
        )
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
                unprocessedCount = items.filter { $0.status == .unprocessed || $0.status == .needsReview }.count

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
                    updated.status = .actionCreated
                    try await inboxRepo.update(updated)
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items[index] = updated
                    }
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
            unprocessedCount = items.filter { $0.status == .unprocessed || $0.status == .needsReview }.count
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
