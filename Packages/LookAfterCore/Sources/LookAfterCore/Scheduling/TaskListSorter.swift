import Foundation

/// Sorting helpers for actionable daily task views.
public enum TaskListSorter {

    /// Today view: overdue → priority → scheduled time → created.
    /// Fixed-time events stay ordered by their scheduled start time.
    public static func sortForToday(_ tasks: [LifeTask], calendar: Calendar = .current, now: Date = Date()) -> [LifeTask] {
        // Cache "today" once — `LifeTask.isOverdue` otherwise rebuilds Calendar.startOfDay
        // on every comparison (O(n log n) times).
        let todayStart = calendar.startOfDay(for: now)
        return tasks.sorted { lhs, rhs in
            compareForToday(lhs, rhs, calendar: calendar, todayStart: todayStart, now: now)
        }
    }

    public static func sortByPriorityThenSchedule(_ tasks: [LifeTask]) -> [LifeTask] {
        tasks.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            switch (lhs.scheduledTime, rhs.scheduledTime) {
            case let (left?, right?): return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.createdAt < rhs.createdAt
            }
        }
    }

    private static func compareForToday(
        _ lhs: LifeTask,
        _ rhs: LifeTask,
        calendar: Calendar,
        todayStart: Date,
        now: Date
    ) -> Bool {
        if lhs.isFixedTimeEvent && rhs.isFixedTimeEvent {
            return (lhs.scheduledTime ?? .distantFuture) < (rhs.scheduledTime ?? .distantFuture)
        }

        let lhsOverdue = isOverdue(lhs, calendar: calendar, todayStart: todayStart, now: now)
        let rhsOverdue = isOverdue(rhs, calendar: calendar, todayStart: todayStart, now: now)
        if lhsOverdue != rhsOverdue {
            return lhsOverdue && !rhsOverdue
        }

        if lhs.isFixedTimeEvent != rhs.isFixedTimeEvent {
            if lhs.isFixedTimeEvent { return (lhs.scheduledTime ?? .distantFuture) < flexibleSortAnchor(rhs) }
            return flexibleSortAnchor(lhs) < (rhs.scheduledTime ?? .distantFuture)
        }

        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }

        switch (lhs.scheduledTime, rhs.scheduledTime) {
        case let (left?, right?): return left < right
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): break
        }

        return lhs.createdAt < rhs.createdAt
    }

    private static func isOverdue(
        _ task: LifeTask,
        calendar: Calendar,
        todayStart: Date,
        now: Date
    ) -> Bool {
        guard task.status.isActive else { return false }
        if let deadline = task.deadline, deadline < now { return true }
        if let scheduledDate = task.scheduledDate {
            return calendar.startOfDay(for: scheduledDate) < todayStart
        }
        return false
    }

    private static func flexibleSortAnchor(_ task: LifeTask) -> Date {
        task.scheduledTime ?? task.deadline ?? .distantFuture
    }
}
