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
    public var heroTaskId: String?
    public var updatedAt: Date

    // Pin Live Activity — execution-aligned display fields.
    public var pinContextLine: String
    public var pinScheduleLabel: String
    public var pinConstraintLabel: String
    public var pinCategoryIcon: String
    public var pinNextUpSummary: String
    public var pinProgressFraction: Double
    public var pinSectionLabel: String
    public var pinWindowStart: Date?
    public var pinWindowEnd: Date?
    
    public init(
        topTaskTitle: String? = nil,
        topTaskMinutes: Int? = nil,
        energyScore: Int = 50,
        energyLevel: String = "Moderate",
        recommendation: String = "Open \(UserFacingCopy.productName) to see your next step.",
        completedTodayCount: Int = 0,
        activeTaskCount: Int = 0,
        sleepHours: Double? = nil,
        stepCount: Int? = nil,
        hrvMs: Int? = nil,
        tasks: [WidgetTaskItem] = [],
        heroTaskId: String? = nil,
        updatedAt: Date = Date(),
        pinContextLine: String = "",
        pinScheduleLabel: String = "",
        pinConstraintLabel: String = "Flexible",
        pinCategoryIcon: String = "sparkles",
        pinNextUpSummary: String = "",
        pinProgressFraction: Double = 0,
        pinSectionLabel: String = "NOW",
        pinWindowStart: Date? = nil,
        pinWindowEnd: Date? = nil
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
        self.heroTaskId = heroTaskId
        self.updatedAt = updatedAt
        self.pinContextLine = pinContextLine
        self.pinScheduleLabel = pinScheduleLabel
        self.pinConstraintLabel = pinConstraintLabel
        self.pinCategoryIcon = pinCategoryIcon
        self.pinNextUpSummary = pinNextUpSummary
        self.pinProgressFraction = min(1, max(0, pinProgressFraction))
        self.pinSectionLabel = pinSectionLabel
        self.pinWindowStart = pinWindowStart
        self.pinWindowEnd = pinWindowEnd
    }
    
    public static let empty = WidgetSnapshot()
}

public extension WidgetSnapshot {
    /// Title to show on pinned Live Activity — falls back to first widget task row.
    var resolvedTopTaskTitle: String? {
        let trimmed = topTaskTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        let fallback = tasks.first?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return fallback.isEmpty ? nil : fallback
    }
}

public enum WidgetAppGroup {
    /// Legacy App Group (current entitlements). Keep until dual-read soak completes (Phase 7).
    public static let legacyIdentifier = "group.com.samaksh.flowos"
    /// Target brand App Group — add to entitlements when dual-registered.
    public static let modernIdentifier = "group.com.lookafter"
    /// Primary write target — still legacy until entitlement dual-register ships.
    public static let identifier = legacyIdentifier
    public static let snapshotKey = "flowos.widget.snapshot"

    /// All group IDs to attempt for read (modern first when available).
    public static var readIdentifiers: [String] {
        [modernIdentifier, legacyIdentifier]
    }
}
