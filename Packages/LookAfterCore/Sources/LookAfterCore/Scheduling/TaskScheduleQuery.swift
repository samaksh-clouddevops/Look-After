import Foundation

/// Single source of truth for which tasks belong on a day and how series duplicates resolve.
public enum TaskScheduleQuery {

    // MARK: - Series identity

    /// Recurrence series keyed by normalized title so duplicate templates collapse to one row.
    public static func seriesKey(for task: LifeTask) -> String {
        if usesTitleBasedRecurrenceKey(for: task) {
            return "recurring|\(OnboardingTaskSeeder.normalizedRoutineTitle(task.title))"
        }
        return TaskReaper.collisionKey(for: task)
    }

    private static func usesTitleBasedRecurrenceKey(for task: LifeTask) -> Bool {
        if task.parentTaskId != nil { return true }
        if TaskRecurrenceEngine.isRecurrenceTemplate(task) { return true }
        if task.tags.contains("daily-routine") { return true }
        if task.isLifeCommitmentTask { return true }
        if task.recurrenceRule != .none && task.parentTaskId == nil && task.scheduledDate != nil {
            return true
        }
        let semanticType = task.semanticProfile?.semanticType
            ?? TaskSemanticProfileBuilder.build(from: task).semanticType
        if semanticType == .physicalActivity {
            return true
        }
        return false
    }

    // MARK: - Day schedule

    /// Active tasks on a day with a concrete schedule window (for overlap detection).
    public static func scheduledActiveTasks(
        from tasks: [LifeTask],
        on day: Date,
        calendar: Calendar = .current
    ) -> [LifeTask] {
        let dayStart = calendar.startOfDay(for: day)
        return tasks.filter { task in
            guard task.status.isActive else { return false }
            return TaskScheduleInterval.window(for: task, on: dayStart, calendar: calendar) != nil
        }
    }

    /// Tasks that belong on a specific day's timeline — scheduled instances only.
    public static func tasksForDay(
        from tasks: [LifeTask],
        allTasks: [LifeTask],
        day: Date,
        calendar: Calendar = .current
    ) -> [LifeTask] {
        TaskSeriesResolver.resolvedTasks(
            allTasks: allTasks,
            options: TaskSeriesResolver.Options(
                day: day,
                includeProjections: true,
                includeCompleted: false,
                activeOnly: true
            ),
            calendar: calendar
        )
    }

    /// Non-keeper ids when multiple occurrence rows share template + scheduled day.
    public static func redundantOccurrenceIDs(
        in group: [LifeTask],
        on day: Date,
        calendar: Calendar = .current
    ) -> [String] {
        guard group.count > 1 else { return [] }
        guard let keeper = preferredKeeper(in: group, on: day, calendar: calendar) else {
            return group.dropFirst().map(\.id)
        }
        return group.filter { $0.id != keeper.id }.map(\.id)
    }

    /// Active tasks for today's list — one instance per series, recurrence-aware.
    public static func activeTasksForToday(
        from tasks: [LifeTask],
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> [LifeTask] {
        let day = calendar.startOfDay(for: referenceDate)
        let candidates = tasks.filter { task in
            guard task.status.isActive else { return false }
            guard !TaskRecurrenceEngine.isRecurrenceTemplate(task) else { return false }
            if task.scheduledDate == nil {
                return true
            }
            return TaskRecurrenceEngine.isActionableToday(
                task,
                in: tasks,
                calendar: calendar,
                referenceDate: referenceDate
            )
        }
        let fulfilledSeries = TaskRecurrenceEngine.fulfilledSeriesKeys(on: day, in: tasks, calendar: calendar)
        let filtered = candidates.filter { !fulfilledSeries.contains(seriesKey(for: $0)) }
        return resolveSeriesConflicts(in: filtered, on: day, calendar: calendar)
    }

    /// Unique active tasks across today, tomorrow, upcoming, backlog, and recurring series.
    /// Excludes completed ad-hoc tasks and recurrence templates (shows occurrence/projection instead).
    public static func uniqueActiveTasks(
        from active: [LifeTask],
        context: [LifeTask],
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> [LifeTask] {
        let day = calendar.startOfDay(for: referenceDate)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let completedTodayIDs = Set(
            context.filter { $0.status == .completed }.map(\.id)
        )

        var candidates: [LifeTask] = []
        for task in active {
            guard task.status.isActive else { continue }
            guard !TaskRecurrenceEngine.isRecurrenceTemplate(task) else { continue }
            guard !completedTodayIDs.contains(task.id) else { continue }

            let isRelevant =
                task.isActionableToday(allTasks: context, calendar: calendar)
                || task.isActionableTomorrow(allTasks: context, calendar: calendar)
                || task.isUpcoming(allTasks: context, calendar: calendar)
                || task.isActiveBacklog(calendar: calendar)
                || task.isScheduledTask(allTasks: context, calendar: calendar)
                || task.isOverdue

            if isRelevant {
                candidates.append(task)
            }
        }

        let todayProjections = TaskRecurrenceEngine.timelineProjections(
            for: context, on: day, calendar: calendar
        )
        let tomorrowProjections = TaskRecurrenceEngine.timelineProjections(
            for: context, on: tomorrow, calendar: calendar
        )
        let storedSeries = Set(candidates.map(seriesKey(for:)))
        let fulfilledSeries = TaskRecurrenceEngine.fulfilledSeriesKeys(on: day, in: context, calendar: calendar)
        for projection in todayProjections + tomorrowProjections {
            let key = seriesKey(for: projection)
            guard !storedSeries.contains(key) else { continue }
            guard !fulfilledSeries.contains(key) else { continue }
            guard !candidates.contains(where: { seriesKey(for: $0) == key }) else { continue }
            candidates.append(projection)
        }

        return resolveSeriesConflicts(in: candidates, on: day, calendar: calendar)
    }

    /// Ids of redundant active instances that should be superseded in storage.
    public static func supersededDuplicateIDs(
        in allTasks: [LifeTask],
        on day: Date = Date(),
        calendar: Calendar = .current
    ) -> [String] {
        TaskSeriesResolver.duplicateGroupNonKeeperIDs(in: allTasks, on: day, calendar: calendar)
    }

    /// Whether `nextDay` already has a scheduled occurrence for the same recurrence template.
    public static func nextDayHasSeriesOccurrence(
        for task: LifeTask,
        in allTasks: [LifeTask],
        nextDay: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let parentId = task.parentTaskId,
              let template = allTasks.first(where: { $0.id == parentId }) else { return false }
        return TaskRecurrenceEngine.hasOccurrence(
            for: template,
            on: nextDay,
            in: allTasks,
            calendar: calendar
        )
    }

    // MARK: - Internal

    public static func resolveSeriesConflicts(
        in tasks: [LifeTask],
        on day: Date,
        calendar: Calendar
    ) -> [LifeTask] {
        var groups: [String: [LifeTask]] = [:]
        for task in tasks {
            groups[seriesKey(for: task), default: []].append(task)
        }

        return groups.keys.sorted().compactMap { key in
            let group = groups[key]!
            if group.count == 1 { return group.first }
            return preferredKeeper(in: group, on: day, calendar: calendar)
        }
    }

    public static func preferredKeeper(
        in group: [LifeTask],
        on day: Date,
        calendar: Calendar
    ) -> LifeTask? {
        group.max { lhs, rhs in
            let leftScore = keeperScore(lhs, on: day, calendar: calendar)
            let rightScore = keeperScore(rhs, on: day, calendar: calendar)
            if leftScore != rightScore { return leftScore < rightScore }
            return lhs.id < rhs.id
        }
    }

    private static func keeperScore(_ task: LifeTask, on day: Date, calendar: Calendar) -> Int {
        var score = 0
        if let scheduledDate = task.scheduledDate, calendar.isDate(scheduledDate, inSameDayAs: day) {
            score += 100
            if TaskScheduleInterval.hasConcreteTimelineSlot(for: task, on: day, calendar: calendar) {
                score += 50
            }
        }
        if task.parentTaskId != nil { score += 20 }
        if task.schedulingMode == .fixedTime { score += 10 }
        if task.tags.contains("daily-routine") { score += 5 }
        return score
    }
}

/// Pure compaction for recurrence occurrence rows — safe to run off the main thread.
public enum TaskRecurrenceCompactor {
    public static func compact(
        _ tasks: [LifeTask],
        retentionDays: Int = 7,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> (tasks: [LifeTask], removedCount: Int) {
        let before = tasks.count
        let dayStart = calendar.startOfDay(for: referenceDate)
        let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: dayStart) ?? dayStart

        var idsToRemove = Set<String>()
        for task in tasks where task.parentTaskId != nil {
            switch task.status {
            case .superseded, .expired:
                idsToRemove.insert(task.id)
            case .skipped:
                let anchor = task.scheduledDate ?? task.updatedAt
                if anchor < cutoff { idsToRemove.insert(task.id) }
            default:
                break
            }
        }

        var groups: [String: [LifeTask]] = [:]
        for task in tasks where task.parentTaskId != nil && !idsToRemove.contains(task.id) {
            guard let scheduledDate = task.scheduledDate else { continue }
            let key = "\(task.parentTaskId!)|\(Int(calendar.startOfDay(for: scheduledDate).timeIntervalSince1970))"
            groups[key, default: []].append(task)
        }
        for (_, group) in groups where group.count > 1 {
            let stale = TaskScheduleQuery.redundantOccurrenceIDs(in: group, on: dayStart, calendar: calendar)
            idsToRemove.formUnion(stale)
        }

        guard !idsToRemove.isEmpty else { return (tasks, 0) }
        var pruned = tasks
        pruned.removeAll { idsToRemove.contains($0.id) }
        return (pruned, before - pruned.count)
    }
}
