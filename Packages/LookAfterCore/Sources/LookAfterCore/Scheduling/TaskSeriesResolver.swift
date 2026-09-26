import Foundation

/// Single primitive for resolving one task row per recurrence series on a day.
public enum TaskSeriesResolver {

    public struct Options: Sendable, Equatable {
        public let day: Date
        public let includeProjections: Bool
        public let includeCompleted: Bool
        public let activeOnly: Bool
        public let referenceDate: Date

        public init(
            day: Date,
            includeProjections: Bool = false,
            includeCompleted: Bool = false,
            activeOnly: Bool = true,
            referenceDate: Date = Date()
        ) {
            self.day = day
            self.includeProjections = includeProjections
            self.includeCompleted = includeCompleted
            self.activeOnly = activeOnly
            self.referenceDate = referenceDate
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
                guard isActiveCandidate(
                    task,
                    on: dayStart,
                    in: allTasks,
                    calendar: calendar,
                    referenceDate: options.referenceDate
                ) else { continue }
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
        let activeTasks = allTasks.filter { task in
            task.status.isActive && !TaskRecurrenceEngine.isRecurrenceTemplate(task)
        }
        let sameDaySeries = Set(
            activeTasks.compactMap { task -> String? in
                guard isScheduled(on: dayStart, task: task, calendar: calendar) else { return nil }
                return TaskScheduleQuery.seriesKey(for: task)
            }
        )
        let active = activeTasks.filter { task in
            belongsInDuplicateGroup(
                on: dayStart,
                task: task,
                sameDaySeries: sameDaySeries,
                calendar: calendar
            )
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
            options: Options(
                day: dayStart,
                includeProjections: false,
                includeCompleted: false,
                activeOnly: true,
                referenceDate: dayStart
            ),
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
        if task.isDeadlineOnlyDue(on: dayStart, calendar: calendar) {
            return true
        }
        return false
    }

    private static func isActiveCandidate(
        _ task: LifeTask,
        on dayStart: Date,
        in allTasks: [LifeTask],
        calendar: Calendar,
        referenceDate: Date
    ) -> Bool {
        guard task.status.isActive else { return false }
        guard task.scheduledDate != nil || task.scheduledTime != nil else {
            // Deadline-only one-offs belong on their due day, and overdue ones carry onto today.
            // Unscheduled backlog stays in the list, not the timeline.
            if task.isDeadlineOnlyDue(on: dayStart, calendar: calendar) {
                return true
            }
            return task.isOverdueOneOffCarryForward(calendar: calendar, referenceDate: referenceDate)
                && calendar.isDate(dayStart, inSameDayAs: referenceDate)
        }
        guard TaskRecurrenceEngine.isActionable(
            on: dayStart,
            task: task,
            in: allTasks,
            calendar: calendar,
            referenceDate: referenceDate
        ) else {
            return false
        }
        let hasSlot = TaskScheduleInterval.hasConcreteTimelineSlot(for: task, on: dayStart, calendar: calendar)
        if hasSlot { return true }
        // Overdue one-offs are actionable today even though `scheduledDate` is yesterday
        // and therefore have no concrete window on `dayStart`. Recurring occurrences stay
        // anchored to their scheduled day.
        if task.isOverdueOneOffCarryForward(calendar: calendar, referenceDate: referenceDate) {
            return calendar.isDate(dayStart, inSameDayAs: referenceDate)
        }
        if TaskScheduleInterval.isPlaceholderMidnightSchedule(for: task, calendar: calendar) {
            if let scheduledDate = task.scheduledDate {
                return calendar.isDate(scheduledDate, inSameDayAs: dayStart)
            }
            if let scheduledTime = task.scheduledTime {
                return calendar.isDate(scheduledTime, inSameDayAs: dayStart)
            }
            return false
        }
        guard task.timeConstraintValue.isSchedulerMovable else { return false }
        guard task.schedulingMode == .flexible
            || task.timeConstraintValue == .flexible
            || task.timeConstraintValue == .fluid else {
            return false
        }
        if let scheduledDate = task.scheduledDate {
            return calendar.isDate(scheduledDate, inSameDayAs: dayStart)
        }
        if let scheduledTime = task.scheduledTime {
            return calendar.isDate(scheduledTime, inSameDayAs: dayStart)
        }
        return false
    }

    private static func isScheduled(
        on dayStart: Date,
        task: LifeTask,
        calendar: Calendar
    ) -> Bool {
        if let scheduled = task.scheduledDate {
            return calendar.isDate(scheduled, inSameDayAs: dayStart)
        }
        // Time-only occurrences still belong to the day encoded in the clock.
        if let scheduledTime = task.scheduledTime {
            return calendar.isDate(scheduledTime, inSameDayAs: dayStart)
        }
        return false
    }

    /// Same-day rows, plus undated or past series rows only when today's occurrence is
    /// already in the group. A lone past occurrence is not a duplicate of itself.
    /// Future occurrences stay on their own day.
    private static func belongsInDuplicateGroup(
        on dayStart: Date,
        task: LifeTask,
        sameDaySeries: Set<String>,
        calendar: Calendar
    ) -> Bool {
        if isScheduled(on: dayStart, task: task, calendar: calendar) { return true }
        let key = TaskScheduleQuery.seriesKey(for: task)
        guard sameDaySeries.contains(key) else { return false }
        guard let scheduled = task.scheduledDate ?? task.scheduledTime else {
            return task.parentTaskId != nil
        }
        let scheduledDay = calendar.startOfDay(for: scheduled)
        guard scheduledDay < dayStart else { return false }
        return task.parentTaskId != nil
            || task.isOverdueOneOffCarryForward(calendar: calendar, referenceDate: dayStart)
    }
}
