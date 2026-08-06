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

    /// Resolves when a task starts on a timeline day — combines date + time-of-day when both exist.
    public static func resolvedStart(
        for task: LifeTask,
        on day: Date,
        calendar: Calendar = .current
    ) -> Date? {
        if let window = window(for: task, on: day, calendar: calendar) {
            return window.start
        }

        if let scheduledDate = task.scheduledDate,
           calendar.isDate(scheduledDate, inSameDayAs: day),
           task.scheduledTime == nil {
            return calendar.startOfDay(for: scheduledDate)
        }

        if let startTime = task.scheduledTime,
           let combined = calendar.combine(date: day, timeFrom: startTime) {
            if let scheduledDate = task.scheduledDate {
                guard calendar.isDate(scheduledDate, inSameDayAs: day) else { return nil }
            }
            return combined
        }

        return nil
    }

    /// Resolves when a task's window ends on a timeline day.
    public static func resolvedEnd(
        for task: LifeTask,
        on day: Date,
        calendar: Calendar = .current
    ) -> Date? {
        if let window = window(for: task, on: day, calendar: calendar) {
            return window.end
        }

        if let scheduledDate = task.scheduledDate,
           calendar.isDate(scheduledDate, inSameDayAs: day),
           task.scheduledTime == nil {
            return DayBoundaryPlanner.actionableDayEnd(on: day, calendar: calendar)
        }

        if let start = resolvedStart(for: task, on: day, calendar: calendar) {
            let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
            return start.addingTimeInterval(TimeInterval(duration * 60))
        }

        return nil
    }

    /// Whether the task has a calendar day but no explicit time-of-day.
    public static func isDateOnlySchedule(
        for task: LifeTask,
        on day: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let scheduledDate = task.scheduledDate,
              calendar.isDate(scheduledDate, inSameDayAs: day) else { return false }
        return task.scheduledTime == nil
    }

    /// Midnight time-of-day usually means the user picked a day, not a clock time.
    public static func isMidnightTimeOfDay(_ time: Date?, calendar: Calendar = .current) -> Bool {
        guard let time else { return true }
        return calendar.component(.hour, from: time) == 0
            && calendar.component(.minute, from: time) == 0
    }

    /// Date-only or midnight-on-day tasks that should show as "Flexible today" on the timeline.
    public static func isFlexibleDaySchedule(
        for task: LifeTask,
        on day: Date,
        calendar: Calendar = .current
    ) -> Bool {
        if isDateOnlySchedule(for: task, on: day, calendar: calendar) {
            return true
        }
        guard let scheduledDate = task.scheduledDate,
              calendar.isDate(scheduledDate, inSameDayAs: day),
              isMidnightTimeOfDay(task.scheduledTime, calendar: calendar) else {
            return false
        }
        return task.schedulingMode != .fixedTime
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
        let end = event.resolvedEndDate(calendar: calendar)
        return rangeLabel(from: event.date, to: end, calendar: calendar)
    }
}

public extension LifeTimelineEvent {
    /// Resolves the end of this event's scheduled window.
    func resolvedEndDate(calendar: Calendar = .current) -> Date {
        if isFlexibleToday {
            return DayBoundaryPlanner.actionableDayEnd(on: date, calendar: calendar)
        }
        if let parsed = ScheduleTimeFormatting.parseRangeEnd(from: subtitle, on: date, calendar: calendar) {
            return parsed
        }
        let minutes = estimatedMinutes ?? 30
        return date.addingTimeInterval(TimeInterval(minutes * 60))
    }

    public var isFlexibleToday: Bool {
        subtitle == "Flexible today" || subtitle.hasSuffix(" · Flexible today")
    }

    /// Display range label preferring subtitle when it already contains a time range.
    var scheduleRangeLabel: String {
        if subtitle.contains(" – "), !subtitle.hasPrefix("About ") {
            let parts = subtitle.components(separatedBy: " · ")
            let rangePart = parts.last ?? subtitle
            if rangePart.contains(" – ") { return rangePart }
        }
        return ScheduleTimeFormatting.rangeLabel(for: self)
    }

    /// Whether this event represents an important fixed commitment for glance views.
    var isImportantCommitment: Bool {
        guard !isCompleted else { return false }
        return isFixed || kind == .meeting || kind == .work
    }
}

public extension ScheduleTimeFormatting {
    /// Parses the end time from a subtitle like `"8:30 AM – 5:30 PM"`.
    static func parseRangeEnd(from subtitle: String, on referenceDay: Date, calendar: Calendar = .current) -> Date? {
        let rangePart: String
        if subtitle.contains(" · "), let last = subtitle.components(separatedBy: " · ").last, last.contains(" – ") {
            rangePart = last
        } else if subtitle.contains(" – ") {
            rangePart = subtitle
        } else {
            return nil
        }

        let segments = rangePart.components(separatedBy: " – ")
        guard segments.count >= 2 else { return nil }
        let endLabel = segments[1].trimmingCharacters(in: .whitespaces)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.calendar = calendar
        guard let parsed = formatter.date(from: endLabel) else { return nil }

        var components = calendar.dateComponents([.year, .month, .day], from: referenceDay)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: parsed)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        return calendar.date(from: components)
    }
}
