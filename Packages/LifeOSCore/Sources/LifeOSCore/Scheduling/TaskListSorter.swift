import Foundation

/// Sorting helpers for actionable daily task views.
public enum TaskListSorter {

    /// Today view: overdue → priority → scheduled time → created.
    /// Fixed-time events stay ordered by their scheduled start time.
    public static func sortForToday(_ tasks: [LifeTask], calendar: Calendar = .current) -> [LifeTask] {
        tasks.sorted { lhs, rhs in
            compareForToday(lhs, rhs, calendar: calendar)
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

    private static func compareForToday(_ lhs: LifeTask, _ rhs: LifeTask, calendar: Calendar) -> Bool {
        if lhs.isFixedTimeEvent && rhs.isFixedTimeEvent {
            return (lhs.scheduledTime ?? .distantFuture) < (rhs.scheduledTime ?? .distantFuture)
        }

        if lhs.isOverdue != rhs.isOverdue {
            return lhs.isOverdue && !rhs.isOverdue
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

    private static func flexibleSortAnchor(_ task: LifeTask) -> Date {
        task.scheduledTime ?? task.deadline ?? .distantFuture
    }
}
