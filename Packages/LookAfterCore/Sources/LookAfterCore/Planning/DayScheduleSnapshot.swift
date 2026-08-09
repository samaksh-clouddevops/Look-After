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
            task.status.isActive && task.scheduledTime != nil
        }
    }

    public func tasks(on day: Date, calendar: Calendar = .current) -> [LifeTask] {
        tasks.filter { task in
            guard let scheduledDate = task.scheduledDate else { return false }
            return calendar.isDate(scheduledDate, inSameDayAs: day)
        }
    }
}
