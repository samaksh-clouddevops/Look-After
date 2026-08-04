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
    public var updatedAt: Date

    // V2
    public var executive: WidgetRecommendation?
    public var today: WidgetTodaySummary?
    public var focus: WidgetFocusState?
    public var medication: WidgetMedicationStatus?
    public var recoveryLabel: String?
    public var hydrationMlToday: Double?
    public var insightLine: String?
    /// False when HealthKit is off or no summary was available at sync time.
    public var hasHealthData: Bool
    public var schemaVersion: Int

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
        updatedAt: Date = Date(),
        executive: WidgetRecommendation? = nil,
        today: WidgetTodaySummary? = nil,
        focus: WidgetFocusState? = nil,
        medication: WidgetMedicationStatus? = nil,
        recoveryLabel: String? = nil,
        hydrationMlToday: Double? = nil,
        insightLine: String? = nil,
        hasHealthData: Bool = false,
        schemaVersion: Int = 2
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
        self.executive = executive
        self.today = today
        self.focus = focus
        self.medication = medication
        self.recoveryLabel = recoveryLabel
        self.hydrationMlToday = hydrationMlToday
        self.insightLine = insightLine
        self.hasHealthData = hasHealthData
        self.schemaVersion = schemaVersion
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

public enum WidgetAppGroup {
    public static let identifier = "group.com.samaksh.flowos"
    public static let snapshotKey = "flowos.widget.snapshot"
    public static let commandQueueKey = "lookafter.widget.commands"
}

/// Stable WidgetKit kind identifiers (V2).
public enum LookAfterWidgetKind {
    public static let recommendation = "LookAfter.Recommendation"
    public static let today = "LookAfter.Today"
    public static let focus = "LookAfter.Focus"
    public static let health = "LookAfter.Health"
    public static let capture = "LookAfter.Capture"
    public static let medication = "LookAfter.Medication"
    public static let calendar = "LookAfter.Calendar"
    public static let habits = "LookAfter.Habits"
    public static let lifeState = "LookAfter.LifeState"
    public static let brain = "LookAfter.Brain"
    public static let weekly = "LookAfter.Weekly"
    public static let memory = "LookAfter.Memory"
    /// V1 (kept one release for migration)
    public static let nowV1 = "NowWidget"
    public static let energyV1 = "EnergyWidget"
    public static let tasksV1 = "TasksWidget"
}

public enum LookAfterDeepLink {
    public static let scheme = "lookafter"
    public static let recommend = URL(string: "lookafter://recommend")!
    public static let today = URL(string: "lookafter://today")!
    public static let focus = URL(string: "lookafter://focus")!
    public static let capture = URL(string: "lookafter://capture")!
    public static let health = URL(string: "lookafter://health")!
    public static let medication = URL(string: "lookafter://medication")!
    public static let brain = URL(string: "lookafter://brain")!

    public static func capture(mode: String) -> URL {
        URL(string: "lookafter://capture?mode=\(mode)") ?? capture
    }

    public static func task(id: String) -> URL {
        URL(string: "lookafter://task/\(id)") ?? recommend
    }
}
