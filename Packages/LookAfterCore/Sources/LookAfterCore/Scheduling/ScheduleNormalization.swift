import Foundation

/// Write-time normalization for schedule fields — prevents midnight sentinel persistence.
public enum ScheduleNormalization {

    /// Strips placeholder midnight times — `00:00` is a day sentinel, never real clock intent.
    public static func normalizeFields(_ task: inout LifeTask, calendar: Calendar = .current) {
        let hadMidnight = TaskScheduleInterval.isMidnightClockTime(task.scheduledTime, calendar: calendar)
            || TaskScheduleInterval.isMidnightClockTime(task.scheduledEndTime, calendar: calendar)
        guard hadMidnight else { return }
        task.userPlacedScheduleAt = nil
        if TaskScheduleInterval.isMidnightClockTime(task.scheduledTime, calendar: calendar) {
            task.scheduledTime = nil
        }
        if TaskScheduleInterval.isMidnightClockTime(task.scheduledEndTime, calendar: calendar) {
            task.scheduledEndTime = nil
        }
    }

    /// Returns a copy with normalized schedule fields.
    public static func normalized(_ task: LifeTask, calendar: Calendar = .current) -> LifeTask {
        var copy = task
        normalizeFields(&copy, calendar: calendar)
        return copy
    }
}
