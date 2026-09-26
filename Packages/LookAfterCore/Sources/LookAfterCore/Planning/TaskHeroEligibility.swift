import Foundation

/// Whether a task may be promoted as the Brain / Briefing "DO THIS NOW" hero at a given moment.
public enum TaskHeroEligibility {

    public enum Status: Sendable, Equatable {
        case eligible
        case inProgress
        case upcoming(minutesUntil: Int)
        case laterToday(minutesUntil: Int)
        case pastWindow
        case unscheduled
    }

    /// Default lookahead for tasks that have not started yet (prep flows, gym, meetings).
    public static let defaultUpcomingGraceMinutes = 60

    public static func status(
        for task: LifeTask,
        now: Date = Date(),
        calendar: Calendar = .current,
        upcomingGraceMinutes: Int = defaultUpcomingGraceMinutes
    ) -> Status {
        if task.status == .inProgress || task.status == .paused {
            return .inProgress
        }

        let day = calendar.startOfDay(for: now)

        if let interval = TaskScheduleInterval.window(for: task, on: day, calendar: calendar) {
            return windowStatus(
                start: interval.start,
                end: interval.end,
                now: now,
                upcomingGraceMinutes: upcomingGraceMinutes
            )
        }

        // Overdue one-offs carry onto today without a concrete clock window. Remapping
        // yesterday's 9am onto today would mark them `.pastWindow` and drop them from
        // hero / pin-now even though they are actionable today.
        if task.isOverdueOneOffCarryForward(calendar: calendar, referenceDate: now) {
            return .unscheduled
        }

        // A scheduledDate on another day must not be remapped — that steals tomorrow
        // (or leftover yesterday) onto the queried day. Time-only clocks belong to
        // the day encoded in the clock itself, not to whatever day is being queried.
        if let scheduledDate = task.scheduledDate ?? task.scheduledTime,
           !calendar.isDate(scheduledDate, inSameDayAs: day) {
            return .unscheduled
        }

        if let time = task.scheduledTime {
            guard let windowStart = calendar.combine(date: day, timeFrom: time) else {
                return .unscheduled
            }
            let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
            let windowEnd: Date
            if let endTime = task.scheduledEndTime,
               let combined = calendar.combine(date: day, timeFrom: endTime),
               combined > windowStart {
                windowEnd = combined
            } else {
                windowEnd = windowStart.addingTimeInterval(TimeInterval(duration * 60))
            }

            return windowStatus(
                start: windowStart,
                end: windowEnd,
                now: now,
                upcomingGraceMinutes: upcomingGraceMinutes
            )
        }

        return .unscheduled
    }

    public static func isEligible(
        for task: LifeTask,
        now: Date = Date(),
        calendar: Calendar = .current,
        allTasks: [LifeTask] = [],
        upcomingGraceMinutes: Int = defaultUpcomingGraceMinutes
    ) -> Bool {
        switch status(for: task, now: now, calendar: calendar, upcomingGraceMinutes: upcomingGraceMinutes) {
        case .pastWindow, .laterToday:
            return false
        case .inProgress:
            return true
        case .eligible, .upcoming, .unscheduled:
            break
        }

        let context = allTasks.isEmpty ? [task] : allTasks
        return TaskRecurrenceEngine.isActionableToday(
            task,
            in: context,
            calendar: calendar,
            referenceDate: now
        )
    }

    public static func isPastWindow(
        for task: LifeTask,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        if case .pastWindow = status(for: task, now: now, calendar: calendar) {
            return true
        }
        return false
    }

    private static func windowStatus(
        start: Date,
        end: Date,
        now: Date,
        upcomingGraceMinutes: Int
    ) -> Status {
        if now > end { return .pastWindow }
        if now < start {
            let minutesUntil = max(0, Int(start.timeIntervalSince(now) / 60))
            return minutesUntil <= upcomingGraceMinutes
                ? .upcoming(minutesUntil: minutesUntil)
                : .laterToday(minutesUntil: minutesUntil)
        }
        return .eligible
    }
}
