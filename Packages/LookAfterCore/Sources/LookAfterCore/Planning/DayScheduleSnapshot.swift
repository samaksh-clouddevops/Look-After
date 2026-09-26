import Foundation

/// Immutable post-reconcile view of today's scheduled tasks — single read contract for consumers.
public struct DayScheduleSnapshot: Sendable, Equatable {
    public let day: Date
    public let tasks: [LifeTask]
    public let reconciledAt: Date
    public let changedTaskIDs: Set<String>

    public init(
        day: Date,
        tasks: [LifeTask] = [],
        reconciledAt: Date = Date(),
        changedTaskIDs: Set<String> = []
    ) {
        self.day = day
        self.tasks = tasks
        self.reconciledAt = reconciledAt
        self.changedTaskIDs = changedTaskIDs
    }

    public static let empty = DayScheduleSnapshot(day: .distantPast)

    public var activeScheduledTasks: [LifeTask] {
        tasks.filter { task in
            task.belongsOnDaySchedule(day: day, calendar: .current, now: reconciledAt)
        }
    }

    public func tasks(on day: Date, calendar: Calendar = .current, now: Date? = nil) -> [LifeTask] {
        let reference = now ?? reconciledAt
        return tasks.filter { task in
            task.belongsOnDaySchedule(day: day, calendar: calendar, now: reference)
        }
    }
}
