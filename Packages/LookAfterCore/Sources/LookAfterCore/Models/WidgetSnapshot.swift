import Foundation

// MARK: - V1 row (retained)

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

// MARK: - V2 payloads

/// Executive Brain recommendation for the primary “what now?” widget.
public struct WidgetRecommendation: Codable, Sendable, Equatable, Hashable {
    public var taskID: String?
    public var title: String
    public var whyLine: String
    public var nextStepLine: String?
    public var estimatedMinutes: Int?
    public var energyLabel: String?
    public var energyScore: Int?

    public init(
        taskID: String? = nil,
        title: String,
        whyLine: String = "",
        nextStepLine: String? = nil,
        estimatedMinutes: Int? = nil,
        energyLabel: String? = nil,
        energyScore: Int? = nil
    ) {
        self.taskID = taskID
        self.title = title
        self.whyLine = whyLine
        self.nextStepLine = nextStepLine
        self.estimatedMinutes = estimatedMinutes
        self.energyLabel = energyLabel
        self.energyScore = energyScore
    }

    public static let clear = WidgetRecommendation(
        title: "You're clear",
        whyLine: "Nothing urgent right now."
    )
}

public struct WidgetTimelineBeat: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var timeLabel: String
    public var title: String
    public var detail: String?
    public var kind: String

    public init(id: String, timeLabel: String, title: String, detail: String? = nil, kind: String = "task") {
        self.id = id
        self.timeLabel = timeLabel
        self.title = title
        self.detail = detail
        self.kind = kind
    }
}

public struct WidgetTodaySummary: Codable, Sendable, Equatable, Hashable {
    public var nextEventTitle: String?
    public var nextEventTimeLabel: String?
    public var nextTaskTitle: String?
    public var freeMinutes: Int?
    public var capacityLabel: String?
    public var beats: [WidgetTimelineBeat]

    public init(
        nextEventTitle: String? = nil,
        nextEventTimeLabel: String? = nil,
        nextTaskTitle: String? = nil,
        freeMinutes: Int? = nil,
        capacityLabel: String? = nil,
        beats: [WidgetTimelineBeat] = []
    ) {
        self.nextEventTitle = nextEventTitle
        self.nextEventTimeLabel = nextEventTimeLabel
        self.nextTaskTitle = nextTaskTitle
        self.freeMinutes = freeMinutes
        self.capacityLabel = capacityLabel
        self.beats = beats
    }

    public static let empty = WidgetTodaySummary()
}

public struct WidgetFocusState: Codable, Sendable, Equatable, Hashable {
    public var isActive: Bool
    public var taskTitle: String?
    public var remainingLabel: String?
    public var sessionEndDate: Date?
    public var isPaused: Bool
    public var isOnBreak: Bool

    public init(
        isActive: Bool = false,
        taskTitle: String? = nil,
        remainingLabel: String? = nil,
        sessionEndDate: Date? = nil,
        isPaused: Bool = false,
        isOnBreak: Bool = false
    ) {
        self.isActive = isActive
        self.taskTitle = taskTitle
        self.remainingLabel = remainingLabel
        self.sessionEndDate = sessionEndDate
        self.isPaused = isPaused
        self.isOnBreak = isOnBreak
    }

    public static let idle = WidgetFocusState()
}

public struct WidgetMedicationStatus: Codable, Sendable, Equatable, Hashable {
    public var id: String?
    public var name: String?
    public var timeLabel: String?
    public var isTaken: Bool
    public var dosage: String?

    public init(
        id: String? = nil,
        name: String? = nil,
        timeLabel: String? = nil,
        isTaken: Bool = false,
        dosage: String? = nil
    ) {
        self.id = id
        self.name = name
        self.timeLabel = timeLabel
        self.isTaken = isTaken
        self.dosage = dosage
    }

    public static let none = WidgetMedicationStatus()
    public var hasMedication: Bool { !(name ?? "").isEmpty }
}

// MARK: - Snapshot (V1 fields + V2 extensions)

/// Shared snapshot written by the app and read by the widget extension.
/// V1 fields remain for existing widgets; V2 nested payloads power Widget System V2.
public struct WidgetSnapshot: Codable, Sendable {
    // V1
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

    /// Resolved recommendation preferring V2 executive payload.
    public var resolvedRecommendation: WidgetRecommendation {
        if let executive { return executive }
        return WidgetRecommendation(
            title: topTaskTitle ?? WidgetRecommendation.clear.title,
            whyLine: recommendation,
            estimatedMinutes: topTaskMinutes,
            energyLabel: energyLevel,
            energyScore: energyScore
        )
    }

    public var isStale: Bool {
        Date().timeIntervalSince(updatedAt) > 6 * 60 * 60
    }

    enum CodingKeys: String, CodingKey {
        case topTaskTitle, topTaskMinutes, energyScore, energyLevel, recommendation
        case completedTodayCount, activeTaskCount, sleepHours, stepCount, hrvMs
        case tasks, updatedAt, executive, today, focus, medication
        case recoveryLabel, hydrationMlToday, insightLine, hasHealthData, schemaVersion
    }

    // Backward-compatible decode: V1 App Group payloads omit V2 keys.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        topTaskTitle = try c.decodeIfPresent(String.self, forKey: .topTaskTitle)
        topTaskMinutes = try c.decodeIfPresent(Int.self, forKey: .topTaskMinutes)
        energyScore = try c.decodeIfPresent(Int.self, forKey: .energyScore) ?? 50
        energyLevel = try c.decodeIfPresent(String.self, forKey: .energyLevel) ?? "Moderate"
        recommendation = try c.decodeIfPresent(String.self, forKey: .recommendation)
            ?? "Open \(UserFacingCopy.productName) to see your next step."
        completedTodayCount = try c.decodeIfPresent(Int.self, forKey: .completedTodayCount) ?? 0
        activeTaskCount = try c.decodeIfPresent(Int.self, forKey: .activeTaskCount) ?? 0
        sleepHours = try c.decodeIfPresent(Double.self, forKey: .sleepHours)
        stepCount = try c.decodeIfPresent(Int.self, forKey: .stepCount)
        hrvMs = try c.decodeIfPresent(Int.self, forKey: .hrvMs)
        tasks = try c.decodeIfPresent([WidgetTaskItem].self, forKey: .tasks) ?? []
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        executive = try c.decodeIfPresent(WidgetRecommendation.self, forKey: .executive)
        today = try c.decodeIfPresent(WidgetTodaySummary.self, forKey: .today)
        focus = try c.decodeIfPresent(WidgetFocusState.self, forKey: .focus)
        medication = try c.decodeIfPresent(WidgetMedicationStatus.self, forKey: .medication)
        recoveryLabel = try c.decodeIfPresent(String.self, forKey: .recoveryLabel)
        hydrationMlToday = try c.decodeIfPresent(Double.self, forKey: .hydrationMlToday)
        insightLine = try c.decodeIfPresent(String.self, forKey: .insightLine)
        let decodedHealth = try c.decodeIfPresent(Bool.self, forKey: .hasHealthData)
        hasHealthData = decodedHealth ?? (sleepHours != nil || stepCount != nil || hrvMs != nil)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }
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
