import Foundation

/// Lightweight task row for home screen widgets.
public struct WidgetTaskItem: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var title: String
    public var estimatedMinutes: Int
    public var priorityLabel: String
    
    public init(id: String, title: String, estimatedMinutes: Int, priorityLabel: String) {
        self.id = id
        self.title = title
        self.estimatedMinutes = estimatedMinutes
        self.priorityLabel = priorityLabel
    }
}

/// Shared snapshot written by the app and read by the widget extension.
public struct WidgetSnapshot: Codable, Sendable {
    public var topTaskTitle: String?
    public var topTaskMinutes: Int?
    public var energyScore: Int
    public var energyLevel: String
    public var recommendation: String
    public var completedTodayCount: Int
    public var activeTaskCount: Int
    public var sleepHours: Double?
    public var stepCount: Int?
    public var hrvMs: Int?
    public var tasks: [WidgetTaskItem]
    public var updatedAt: Date
    
    public init(
        topTaskTitle: String? = nil,
        topTaskMinutes: Int? = nil,
        energyScore: Int = 50,
        energyLevel: String = "Moderate",
        recommendation: String = "Open FlowOS to see your next step.",
        completedTodayCount: Int = 0,
        activeTaskCount: Int = 0,
        sleepHours: Double? = nil,
        stepCount: Int? = nil,
        hrvMs: Int? = nil,
        tasks: [WidgetTaskItem] = [],
        updatedAt: Date = Date()
    ) {
        self.topTaskTitle = topTaskTitle
        self.topTaskMinutes = topTaskMinutes
        self.energyScore = energyScore
        self.energyLevel = energyLevel
        self.recommendation = recommendation
        self.completedTodayCount = completedTodayCount
        self.activeTaskCount = activeTaskCount
        self.sleepHours = sleepHours
        self.stepCount = stepCount
        self.hrvMs = hrvMs
        self.tasks = tasks
        self.updatedAt = updatedAt
    }
    
    public static let empty = WidgetSnapshot()
}

public enum WidgetAppGroup {
    public static let identifier = "group.com.samaksh.flowos"
    public static let snapshotKey = "flowos.widget.snapshot"
}
