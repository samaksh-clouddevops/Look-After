import Foundation

/// Detects schedule rows whose window ended more than `grace` ago and are still incomplete.
public enum OverdueTimelineDetector {
    public static let defaultGrace: TimeInterval = 2 * 60 * 60

    public static func overdueTaskRows(
        from rows: [ExecutivePlanningTimelineRow],
        now: Date = Date(),
        grace: TimeInterval = defaultGrace
    ) -> [ExecutivePlanningTimelineRow] {
        rows.filter { row in
            guard let taskId = row.taskId, !taskId.isEmpty else { return false }
            guard !row.isCompleted, !row.isSuggestedSlot else { return false }
            guard row.kind != .medication, row.kind != .bill else { return false }
            let end = estimatedEnd(for: row)
            return end.addingTimeInterval(grace) < now
        }
    }

    private static func estimatedEnd(for row: ExecutivePlanningTimelineRow) -> Date {
        if let minutes = row.estimatedMinutes, minutes > 0 {
            return row.sortDate.addingTimeInterval(TimeInterval(minutes * 60))
        }
        // Fixed events without duration — treat sortDate as the deadline.
        return row.sortDate
    }
}
