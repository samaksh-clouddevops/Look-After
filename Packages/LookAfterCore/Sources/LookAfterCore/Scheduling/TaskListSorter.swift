import Foundation

/// Sorting helpers for actionable daily task views.
public enum TaskListSorter {

    /// Today / All Tasks: overdue → clock time → flexible → priority → created.
    /// Timed work (Morning review) stays before evening anchors (Dinner).
    public static func sortForToday(_ tasks: [LifeTask], calendar: Calendar = .current, now: Date = Date()) -> [LifeTask] {
        // Cache "today" once — `LifeTask.isOverdue` otherwise rebuilds Calendar.startOfDay
        // on every comparison (O(n log n) times).
        let todayStart = calendar.startOfDay(for: now)
        return tasks.sorted { lhs, rhs in
            compareForToday(lhs, rhs, calendar: calendar, todayStart: todayStart, now: now)
        }
    }

    /// Top Priorities: next actionable clock time, then priority.
    public static func sortByNextActionableThenPriority(
        _ tasks: [LifeTask],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [LifeTask] {
        let day = calendar.startOfDay(for: now)
        return tasks.sorted { lhs, rhs in
            let left = nextActionableTime(for: lhs, on: day, calendar: calendar)
            let right = nextActionableTime(for: rhs, on: day, calendar: calendar)
            if left != right { return left < right }
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id < rhs.id
        }
    }

    public static func sortByPriorityThenSchedule(_ tasks: [LifeTask]) -> [LifeTask] {
        tasks.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            switch (lhs.scheduledTime, rhs.scheduledTime) {
            case let (left?, right?): return left == right ? lhs.id < rhs.id : left < right
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil):
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id < rhs.id
            }
        }
    }

    /// Next actionable clock time for Top Priorities — flexible / untimed sort last.
    public static func nextActionableTime(
        for task: LifeTask,
        on day: Date,
        calendar: Calendar = .current
    ) -> Date {
        switch TaskScheduleInterval.displaySchedule(for: task, on: day, calendar: calendar) {
        case .window(let start, _, _):
            return start
        case .unslottedFlexible:
            return .distantFuture
        case .noSchedule:
            return task.deadline ?? .distantFuture
        }
    }

    private static func compareForToday(
        _ lhs: LifeTask,
        _ rhs: LifeTask,
        calendar: Calendar,
        todayStart: Date,
        now: Date
    ) -> Bool {
        let lhsOverdue = isOverdue(lhs, calendar: calendar, todayStart: todayStart, now: now)
        let rhsOverdue = isOverdue(rhs, calendar: calendar, todayStart: todayStart, now: now)
        if lhsOverdue != rhsOverdue {
            return lhsOverdue && !rhsOverdue
        }

        let leftAnchor = scheduleSortAnchor(lhs, calendar: calendar, day: todayStart)
        let rightAnchor = scheduleSortAnchor(rhs, calendar: calendar, day: todayStart)
        if leftAnchor != rightAnchor {
            return leftAnchor < rightAnchor
        }

        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }

        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id < rhs.id
    }

    /// Concrete clock time when available; flexible / untimed sink to the end of the day list.
    private static func scheduleSortAnchor(
        _ task: LifeTask,
        calendar: Calendar,
        day: Date
    ) -> Date {
        if let time = TaskScheduleInterval.timelineDisplayTime(for: task, on: day, calendar: calendar) {
            return time
        }
        // Prefer the task's own day when listing "All" so tomorrow stays after today.
        if let scheduledDate = task.scheduledDate {
            let taskDay = calendar.startOfDay(for: scheduledDate)
            if let time = TaskScheduleInterval.timelineDisplayTime(for: task, on: taskDay, calendar: calendar) {
                return time
            }
            // Flexible on a known day: after that day's timed work.
            return taskDay.addingTimeInterval(24 * 3600 - 1)
        }
        return .distantFuture
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
}
