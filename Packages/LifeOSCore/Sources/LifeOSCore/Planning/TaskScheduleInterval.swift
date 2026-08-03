import Foundation

/// A task's scheduled time window on a specific calendar day.
public struct TaskScheduleInterval: Sendable, Equatable {
    public let taskID: String
    public let start: Date
    public let end: Date

    public init(taskID: String, start: Date, end: Date) {
        self.taskID = taskID
        self.start = start
        self.end = end
    }

    public var durationMinutes: Int {
        max(Int(end.timeIntervalSince(start) / 60), TaskDurationPolicy.minimumMinutes)
    }

    public func overlaps(_ other: TaskScheduleInterval) -> Bool {
        start < other.end && other.start < end
    }

    public func overlaps(start otherStart: Date, end otherEnd: Date) -> Bool {
        start < otherEnd && otherStart < end
    }

    /// Builds the scheduled window for a task on a given day.
    public static func window(
        for task: LifeTask,
        on day: Date,
        calendar: Calendar = .current
    ) -> TaskScheduleInterval? {
        guard let scheduledDate = task.scheduledDate,
              calendar.isDate(scheduledDate, inSameDayAs: day),
              let startTime = task.scheduledTime,
              let start = calendar.combine(date: day, timeFrom: startTime) else {
            return nil
        }

        let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
        let end: Date
        if let endTime = task.scheduledEndTime,
           let combined = calendar.combine(date: day, timeFrom: endTime),
           combined > start {
            end = combined
        } else {
            end = start.addingTimeInterval(TimeInterval(duration * 60))
        }

        return TaskScheduleInterval(taskID: task.id, start: start, end: end)
    }

    /// All scheduled intervals for tasks on a given day, sorted by start time.
    public static func intervals(
        from tasks: [LifeTask],
        on day: Date,
        calendar: Calendar = .current
    ) -> [TaskScheduleInterval] {
        tasks.compactMap { window(for: $0, on: day, calendar: calendar) }
            .sorted { $0.start < $1.start }
    }

    /// End of a task's window — prefers explicit end time, else start + duration.
    public static func endDate(
        for task: LifeTask,
        on day: Date,
        calendar: Calendar = .current
    ) -> Date? {
        window(for: task, on: day, calendar: calendar)?.end
    }
}

/// Formats schedule times for timeline display.
public enum ScheduleTimeFormatting {
    public static func timeLabel(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.calendar = calendar
        return formatter.string(from: date)
    }

    public static func rangeLabel(from start: Date, to end: Date, calendar: Calendar = .current) -> String {
        "\(timeLabel(start, calendar: calendar)) – \(timeLabel(end, calendar: calendar))"
    }

    public static func rangeLabel(for event: LifeTimelineEvent, calendar: Calendar = .current) -> String {
        let end = event.date.addingTimeInterval(TimeInterval((event.estimatedMinutes ?? 30) * 60))
        return rangeLabel(from: event.date, to: end, calendar: calendar)
    }
}
