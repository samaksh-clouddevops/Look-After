import CoreGraphics
import Foundation

/// Maps vertical drag offset on the timeline to snapped clock times.
public enum TimelineDragTimeMapping {
    /// ~48pt ≈ 15 minutes (matches legacy drag heuristic inverted).
    public static let pointsPerMinute: CGFloat = 48.0 / 15.0
    public static let snapIntervalMinutes = 15

    public static func offsetMinutes(from verticalOffset: CGFloat) -> Int {
        let raw = Double(verticalOffset) / Double(pointsPerMinute)
        let snapped = (raw / Double(snapIntervalMinutes)).rounded() * Double(snapIntervalMinutes)
        return Int(snapped)
    }

    public static func proposedStart(
        baseline: Date,
        verticalOffset: CGFloat,
        calendar: Calendar = .current
    ) -> Date {
        let minutes = offsetMinutes(from: verticalOffset)
        return calendar.date(byAdding: .minute, value: minutes, to: baseline) ?? baseline
    }

    public static func snappedMinuteComponent(for verticalOffset: CGFloat) -> Int {
        let total = offsetMinutes(from: verticalOffset)
        let baseline = total >= 0 ? total : (total % snapIntervalMinutes + snapIntervalMinutes) % snapIntervalMinutes
        return baseline % 60
    }
}
