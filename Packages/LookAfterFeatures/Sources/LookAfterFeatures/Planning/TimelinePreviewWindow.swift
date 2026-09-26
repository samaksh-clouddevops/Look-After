import Foundation

/// NOW-centered window for the Today Schedule preview (2 past + current + 2 next).
public enum TimelinePreviewWindow {
    public static let pastCount = 2
    public static let futureCount = 2
    public static var maxVisibleRows: Int { pastCount + 1 + futureCount }

    /// Returns a slice of `rows` centered on the current moment, including completed rows.
    public static func centered(
        rows: [ExecutivePlanningTimelineRow],
        now: Date = Date(),
        past: Int = pastCount,
        future: Int = futureCount
    ) -> [ExecutivePlanningTimelineRow] {
        guard !rows.isEmpty else { return [] }
        let focus = focusIndex(in: rows, now: now)
        let start = max(0, focus - past)
        let end = min(rows.count, focus + future + 1)
        return Array(rows[start..<end])
    }

    public static func hasMoreThanWindow(
        rows: [ExecutivePlanningTimelineRow],
        now: Date = Date(),
        past: Int = pastCount,
        future: Int = futureCount
    ) -> Bool {
        rows.count > centered(rows: rows, now: now, past: past, future: future).count
    }

    private static func focusIndex(in rows: [ExecutivePlanningTimelineRow], now: Date) -> Int {
        if let nowIndex = rows.firstIndex(where: { $0.isNow && !$0.isCompleted }) {
            return nowIndex
        }
        if let lateIndex = rows.firstIndex(where: { $0.isLate && !$0.isCompleted }) {
            return lateIndex
        }
        if let upcoming = rows.firstIndex(where: { !$0.isCompleted && $0.sortDate >= now }) {
            return upcoming
        }
        if let lastIncomplete = rows.lastIndex(where: { !$0.isCompleted }) {
            return lastIncomplete
        }
        return max(0, rows.count - 1)
    }
}
