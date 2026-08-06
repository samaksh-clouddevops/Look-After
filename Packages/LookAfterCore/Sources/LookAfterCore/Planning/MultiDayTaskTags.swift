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
