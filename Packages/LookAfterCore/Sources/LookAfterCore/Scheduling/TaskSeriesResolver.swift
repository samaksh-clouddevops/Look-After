import Foundation

/// Single primitive for resolving one task row per recurrence series on a day.
public enum TaskSeriesResolver {

    public struct Options: Sendable, Equatable {
        public let day: Date
        public let includeProjections: Bool
        public let includeCompleted: Bool
        public let activeOnly: Bool

        public init(
            day: Date,
            includeProjections: Bool = false,
            includeCompleted: Bool = false,
            activeOnly: Bool = true
        ) {
            self.day = day
            self.includeProjections = includeProjections
            self.includeCompleted = includeCompleted
            self.activeOnly = activeOnly
        }
    }

    /// Returns one keeper per seriesKey for the requested day mix.
    public static func resolvedTasks(
        allTasks: [LifeTask],
        options: Options,
        calendar: Calendar = .current
    ) -> [LifeTask] {
        let dayStart = calendar.startOfDay(for: options.day)
        let fulfilledSeries = TaskRecurrenceEngine.fulfilledSeriesKeys(
            on: dayStart,
            in: allTasks,
            calendar: calendar
        )

        var candidates: [LifeTask] = []

        for task in allTasks {
            guard !TaskRecurrenceEngine.isRecurrenceTemplate(task) else { continue }
            guard !MultiDayTaskTags.isRoot(task) else { continue }

            if options.activeOnly, !task.status.isActive { continue }
            if !options.activeOnly, task.status == .superseded || task.status == .expired { continue }

            if task.status.isActive {
                let key = TaskScheduleQuery.seriesKey(for: task)
                if fulfilledSeries.contains(key) { continue }
            }

            if task.status == .completed {
                guard options.includeCompleted else { continue }
                guard isCompletedOnDay(task, dayStart: dayStart, calendar: calendar) else { continue }
            } else if task.status.isActive {
                guard isActiveCandidate(task, on: dayStart, in: allTasks, calendar: calendar) else { continue }
            } else if !options.includeCompleted {
                continue
            }

            candidates.append(task)
        }

        if options.includeProjections {
            let storedSeries = Set(candidates.map { TaskScheduleQuery.seriesKey(for: $0) })
            let projected = TaskRecurrenceEngine.timelineProjections(
                for: allTasks,
                on: dayStart,
                calendar: calendar
            )
            for projection in projected {
                let key = TaskScheduleQuery.seriesKey(for: projection)
                guard !storedSeries.contains(key) else { continue }
                guard !fulfilledSeries.contains(key) else { continue }
                candidates.append(projection)
            }
        }

        return TaskScheduleQuery.resolveSeriesConflicts(in: candidates, on: dayStart, calendar: calendar)
    }

    /// Active task ids that should be superseded — non-keepers in duplicate groups plus fulfilled-series actives.
    public static func staleActiveSeriesIDs(
        in allTasks: [LifeTask],
        on day: Date = Date(),
        calendar: Calendar = .current
    ) -> [String] {
        let dayStart = calendar.startOfDay(for: day)
        var ids = Set(duplicateGroupNonKeeperIDs(in: allTasks, on: dayStart, calendar: calendar))

        let fulfilledSeries = TaskRecurrenceEngine.fulfilledSeriesKeys(
            on: dayStart,
            in: allTasks,
            calendar: calendar
        )
        for task in allTasks where task.status.isActive && !TaskRecurrenceEngine.isRecurrenceTemplate(task) {
            let key = TaskScheduleQuery.seriesKey(for: task)
            guard fulfilledSeries.contains(key) else { continue }
            guard isScheduled(on: dayStart, task: task, calendar: calendar) else { continue }
            ids.insert(task.id)
        }

        ids.formUnion(
            TaskRecurrenceEngine.recurringDuplicateIDsOfLifeCommitments(
                in: allTasks,
                calendar: calendar,
                referenceDate: dayStart
            )
        )

        return Array(ids)
    }

    /// Non-keeper ids when multiple active rows share a seriesKey.
    public static func duplicateGroupNonKeeperIDs(
        in allTasks: [LifeTask],
        on day: Date,
        calendar: Calendar = .current
    ) -> [String] {
        let dayStart = calendar.startOfDay(for: day)
        let active = allTasks.filter { task in
            guard task.status.isActive && !TaskRecurrenceEngine.isRecurrenceTemplate(task) else { return false }
            return isScheduled(on: dayStart, task: task, calendar: calendar)
        }
        var groups: [String: [LifeTask]] = [:]
        for task in active {
            groups[TaskScheduleQuery.seriesKey(for: task), default: []].append(task)
        }

        var stale: [String] = []
        for (_, group) in groups where group.count > 1 {
            guard let keeper = TaskScheduleQuery.preferredKeeper(in: group, on: dayStart, calendar: calendar) else {
                continue
            }
            stale.append(contentsOf: group.filter { $0.id != keeper.id }.map(\.id))
        }
        return stale
    }

    /// True when an active keeper or fulfilled series already exists for this title/day.
    public static func shouldSkipMaterialization(
        for template: LifeTask,
        on day: Date,
        in allTasks: [LifeTask],
        calendar: Calendar = .current
    ) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        if TaskRecurrenceEngine.isSeriesFulfilled(on: dayStart, for: template, in: allTasks, calendar: calendar) {
            return true
        }
        let key = TaskScheduleQuery.seriesKey(for: template)
        let activeKeepers = resolvedTasks(
            allTasks: allTasks,
            options: Options(day: dayStart, includeProjections: false, includeCompleted: false, activeOnly: true),
            calendar: calendar
        )
        return activeKeepers.contains { TaskScheduleQuery.seriesKey(for: $0) == key }
    }

    // MARK: - Private

    private static func isCompletedOnDay(
        _ task: LifeTask,
        dayStart: Date,
        calendar: Calendar
    ) -> Bool {
        guard task.status == .completed else { return false }
        if let completedAt = task.completedAt, calendar.isDate(completedAt, inSameDayAs: dayStart) {
            return true
        }
        if let scheduled = task.scheduledDate, calendar.isDate(scheduled, inSameDayAs: dayStart) {
            return true
        }
        return false
    }

    private static func isActiveCandidate(
        _ task: LifeTask,
        on dayStart: Date,
        in allTasks: [LifeTask],
        calendar: Calendar
    ) -> Bool {
        guard task.status.isActive else { return false }
        guard task.scheduledDate != nil || task.scheduledTime != nil else {
            return calendar.isDateInToday(dayStart)
        }
        guard TaskRecurrenceEngine.isActionable(on: dayStart, task: task, in: allTasks, calendar: calendar) else {
            return false
        }
        let hasSlot = TaskScheduleInterval.hasConcreteTimelineSlot(for: task, on: dayStart, calendar: calendar)
        if hasSlot { return true }
        if TaskScheduleInterval.isPlaceholderMidnightSchedule(for: task, calendar: calendar) {
            return task.scheduledDate.map { calendar.isDate($0, inSameDayAs: dayStart) } ?? true
        }
        guard task.timeConstraintValue.isSchedulerMovable else { return false }
        guard task.schedulingMode == .flexible
            || task.timeConstraintValue == .flexible
            || task.timeConstraintValue == .fluid else {
            return false
        }
        return task.scheduledDate.map { calendar.isDate($0, inSameDayAs: dayStart) } ?? true
    }

    private static func isScheduled(on dayStart: Date, task: LifeTask, calendar: Calendar) -> Bool {
        guard let scheduled = task.scheduledDate else {
            return calendar.isDateInToday(dayStart)
        }
        return calendar.isDate(scheduled, inSameDayAs: dayStart)
    }
}
