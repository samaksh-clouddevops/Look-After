import Foundation

/// Tags for multi-day goal planning — parent container and daily slice tasks.
public enum MultiDayTaskTags {
    public static let root = "multi-day-root"
    public static let slice = "multi-day-slice"

    public static func isRoot(_ task: LifeTask) -> Bool {
        task.tags.contains(root)
    }

    public static func isSlice(_ task: LifeTask) -> Bool {
        task.tags.contains(slice)
    }

    public static func isMultiDay(_ task: LifeTask) -> Bool {
        isRoot(task) || isSlice(task)
    }
}

/// Banner presentation for an active multi-day goal.
public struct MultiDayBannerData: Sendable, Equatable {
    public var title: String
    public var dayIndex: Int
    public var dayCount: Int
    public var sliceTitle: String

    public init(title: String, dayIndex: Int, dayCount: Int, sliceTitle: String) {
        self.title = title
        self.dayIndex = dayIndex
        self.dayCount = dayCount
        self.sliceTitle = sliceTitle
    }
}

/// Suggests splitting an oversized single-task time estimate into a multi-day plan.
public struct MultiDaySuggestion: Sendable, Equatable {
    public var totalMinutes: Int
    public var dayCount: Int
    public var perDayMinutes: Int

    public init(totalMinutes: Int, dayCount: Int, perDayMinutes: Int) {
        self.totalMinutes = totalMinutes
        self.dayCount = dayCount
        self.perDayMinutes = perDayMinutes
    }

    /// Minimum raw minute value that triggers a suggestion — anything past the single-task
    /// ceiling (`TaskDurationPolicy.maximumMinutes`) implies the user meant a bigger goal.
    public static let thresholdMinutes = TaskDurationPolicy.maximumMinutes

    /// Purely arithmetic — no LLM call needed, mirrors `MultiDayTaskPlanner`'s offline fallback.
    public static func suggest(
        forRawMinutes minutes: Int,
        workdayMinutes: Int = TaskDurationPolicy.maximumMinutes
    ) -> MultiDaySuggestion? {
        guard minutes > thresholdMinutes else { return nil }
        let perDay = max(1, workdayMinutes)
        let dayCount = Int((Double(minutes) / Double(perDay)).rounded(.up))
        return MultiDaySuggestion(
            totalMinutes: minutes,
            dayCount: max(2, min(dayCount, 90)),
            perDayMinutes: perDay
        )
    }
}
