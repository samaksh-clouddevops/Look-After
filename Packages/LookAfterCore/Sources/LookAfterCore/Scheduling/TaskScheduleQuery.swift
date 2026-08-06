import Foundation

/// Single source of truth for which tasks belong on a day and how series duplicates resolve.
public enum TaskScheduleQuery {

    // MARK: - Series identity

    /// Recurrence series are keyed by template id; everything else uses semantic collision keys.
    public static func seriesKey(for task: LifeTask) -> String {
        if let parentId = task.parentTaskId, !parentId.isEmpty {
            return "series|\(parentId)"
        }
        if TaskRecurrenceEngine.isRecurrenceTemplate(task) {
            return "template|\(task.id)"
        }
        return TaskReaper.collisionKey(for: task)
    }

    // MARK: - Day schedule

    /// Tasks that belong on a specific day's timeline — scheduled instances only.
    public static func tasksForDay(
        from tasks: [LifeTask],
        allTasks: [LifeTask],
        day: Date,
        calendar: Calendar = .current
    ) -> [LifeTask] {
        let dayStart = calendar.startOfDay(for: day)
        let stored = tasks.filter { task in
            guard !TaskRecurrenceEngine.isRecurrenceTemplate(task) else { return false }
            guard !MultiDayTaskTags.isRoot(task) else { return false }
            guard task.scheduledDate != nil || task.scheduledTime != nil else { return false }
            return TaskRecurrenceEngine.isActionable(on: dayStart, task: task, in: allTasks, calendar: calendar)
        }
        let projected = TaskRecurrenceEngine.timelineProjections(for: allTasks, on: dayStart, calendar: calendar)
        let storedSeries = Set(stored.map(seriesKey(for:)))
        let additions = projected.filter { !storedSeries.contains(seriesKey(for: $0)) }
        return resolveSeriesConflicts(in: stored + additions, on: dayStart, calendar: calendar)
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
        return resolveSeriesConflicts(in: candidates, on: day, calendar: calendar)
    }

    /// Ids of redundant active instances that should be superseded in storage.
    public static func supersededDuplicateIDs(
        in allTasks: [LifeTask],
        on day: Date = Date(),
        calendar: Calendar = .current
    ) -> [String] {
        let dayStart = calendar.startOfDay(for: day)
        let active = allTasks.filter { $0.status.isActive && !TaskRecurrenceEngine.isRecurrenceTemplate($0) }
        var groups: [String: [LifeTask]] = [:]
        for task in active {
            groups[seriesKey(for: task), default: []].append(task)
        }

        var stale: [String] = []
        for (_, group) in groups where group.count > 1 {
            guard let keeper = preferredKeeper(in: group, on: dayStart, calendar: calendar) else { continue }
            stale.append(contentsOf: group.filter { $0.id != keeper.id }.map(\.id))
        }
        return stale
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

    static func resolveSeriesConflicts(
        in tasks: [LifeTask],
        on day: Date,
        calendar: Calendar
    ) -> [LifeTask] {
        var groups: [String: [LifeTask]] = [:]
        for task in tasks {
            groups[seriesKey(for: task), default: []].append(task)
        }

        return groups.values.compactMap { group in
            if group.count == 1 { return group.first }
            return preferredKeeper(in: group, on: day, calendar: calendar)
        }
    }

    static func preferredKeeper(
        in group: [LifeTask],
        on day: Date,
        calendar: Calendar
    ) -> LifeTask? {
        group.max { lhs, rhs in
            keeperScore(lhs, on: day, calendar: calendar) < keeperScore(rhs, on: day, calendar: calendar)
        }
    }

    private static func keeperScore(_ task: LifeTask, on day: Date, calendar: Calendar) -> Int {
        var score = 0
        if let scheduledDate = task.scheduledDate, calendar.isDate(scheduledDate, inSameDayAs: day) {
            score += 100
            if task.scheduledTime != nil { score += 50 }
        }
        if task.parentTaskId != nil { score += 20 }
        if task.schedulingMode == .fixedTime { score += 10 }
        if task.tags.contains("daily-routine") { score += 5 }
        return score
    }
}
