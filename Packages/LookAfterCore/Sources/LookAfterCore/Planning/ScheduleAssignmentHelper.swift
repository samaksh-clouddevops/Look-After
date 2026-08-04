import Foundation

/// Applies start times to tasks while avoiding same-day overlaps.
public enum ScheduleAssignmentHelper {

    /// Returns a start time at or after `proposed` that does not overlap existing tasks.
    public static func scheduledTimeAvoidingOverlap(
        proposed: Date,
        task: LifeTask,
        existingTasks: [LifeTask],
        on day: Date,
        calendar: Calendar = .current,
        bufferMinutes: Int = 5
    ) -> Date {
        let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
        let others = existingTasks.filter { $0.id != task.id && $0.scheduledTime != nil }
        let intervals = TaskScheduleInterval.intervals(from: others, on: day, calendar: calendar)
        guard !intervals.isEmpty else { return proposed }

        var candidate = proposed
        for _ in 0..<96 {
            let end = candidate.addingTimeInterval(TimeInterval(duration * 60))
            let probe = TaskScheduleInterval(taskID: task.id, start: candidate, end: end)
            if !intervals.contains(where: { probe.overlaps($0) }) {
                return candidate
            }
            if let conflict = intervals.first(where: { probe.overlaps($0) }) {
                candidate = conflict.end.addingTimeInterval(TimeInterval(bufferMinutes * 60))
            } else {
                candidate = calendar.date(byAdding: .minute, value: 15, to: candidate) ?? candidate
            }
        }
        return proposed
    }

    public static func applySchedule(
        to task: inout LifeTask,
        start: Date,
        on day: Date,
        calendar: Calendar = .current
    ) {
        task.scheduledDate = calendar.startOfDay(for: day)
        task.scheduledTime = start
        let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
        task.scheduledEndTime = start.addingTimeInterval(TimeInterval(duration * 60))
    }
}
