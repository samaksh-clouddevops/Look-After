import Foundation
import LookAfterCore

/// Computes the time window freed when a task is removed from today's timeline.
public enum FreedSlotWindow {
    public static func from(
        task: LifeTask,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DayReplanAwayWindow? {
        let day = calendar.startOfDay(for: now)
        let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)

        if let window = TaskScheduleInterval.window(for: task, on: day, calendar: calendar) {
            guard window.end > window.start else { return nil }
            return DayReplanAwayWindow(start: window.start, end: window.end)
        }

        let start = max(now, day)
        let end = start.addingTimeInterval(TimeInterval(duration * 60))
        guard end > start else { return nil }
        return DayReplanAwayWindow(start: start, end: end)
    }

    public static func slotMinutes(_ window: DayReplanAwayWindow) -> Int {
        max(Int(window.end.timeIntervalSince(window.start) / 60), TaskDurationPolicy.minimumMinutes)
    }
}
