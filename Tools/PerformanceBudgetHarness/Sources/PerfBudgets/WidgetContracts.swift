import Foundation

/// Pure-Foundation mirrors of Widget System V2 contracts for Linux/Docker CI.
/// Keep in sync with Packages/LookAfterCore Models/WidgetSnapshot.swift.

public struct WidgetTaskItemMirror: Codable, Equatable {
    public var id: String
    public var title: String
    public var estimatedMinutes: Int
    public var priorityLabel: String
}

public struct WidgetRecommendationMirror: Codable, Equatable {
    public var taskID: String?
    public var title: String
    public var whyLine: String
    public var estimatedMinutes: Int?
    public var energyScore: Int?
}

public struct WidgetSnapshotMirror: Codable, Equatable {
    public var topTaskTitle: String?
    public var topTaskMinutes: Int?
    public var energyScore: Int
    public var energyLevel: String
    public var recommendation: String
    public var completedTodayCount: Int
    public var activeTaskCount: Int
    public var tasks: [WidgetTaskItemMirror]
    public var updatedAt: Date
    public var executive: WidgetRecommendationMirror?
    public var recoveryLabel: String?
    public var schemaVersion: Int

    public init(
        topTaskTitle: String? = nil,
        topTaskMinutes: Int? = nil,
        energyScore: Int = 50,
        energyLevel: String = "Moderate",
        recommendation: String = "Open Look After",
        completedTodayCount: Int = 0,
        activeTaskCount: Int = 0,
        tasks: [WidgetTaskItemMirror] = [],
        updatedAt: Date = Date(),
        executive: WidgetRecommendationMirror? = nil,
        recoveryLabel: String? = nil,
        schemaVersion: Int = 2
    ) {
        self.topTaskTitle = topTaskTitle
        self.topTaskMinutes = topTaskMinutes
        self.energyScore = energyScore
        self.energyLevel = energyLevel
        self.recommendation = recommendation
        self.completedTodayCount = completedTodayCount
        self.activeTaskCount = activeTaskCount
        self.tasks = tasks
        self.updatedAt = updatedAt
        self.executive = executive
        self.recoveryLabel = recoveryLabel
        self.schemaVersion = schemaVersion
    }

    public var isStale: Bool {
        Date().timeIntervalSince(updatedAt) > 6 * 60 * 60
    }

    public var resolvedTitle: String {
        executive?.title ?? topTaskTitle ?? "You're clear"
    }

    enum CodingKeys: String, CodingKey {
        case topTaskTitle, topTaskMinutes, energyScore, energyLevel, recommendation
        case completedTodayCount, activeTaskCount, tasks, updatedAt
        case executive, recoveryLabel, schemaVersion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        topTaskTitle = try c.decodeIfPresent(String.self, forKey: .topTaskTitle)
        topTaskMinutes = try c.decodeIfPresent(Int.self, forKey: .topTaskMinutes)
        energyScore = try c.decodeIfPresent(Int.self, forKey: .energyScore) ?? 50
        energyLevel = try c.decodeIfPresent(String.self, forKey: .energyLevel) ?? "Moderate"
        recommendation = try c.decodeIfPresent(String.self, forKey: .recommendation) ?? "Open Look After"
        completedTodayCount = try c.decodeIfPresent(Int.self, forKey: .completedTodayCount) ?? 0
        activeTaskCount = try c.decodeIfPresent(Int.self, forKey: .activeTaskCount) ?? 0
        tasks = try c.decodeIfPresent([WidgetTaskItemMirror].self, forKey: .tasks) ?? []
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        executive = try c.decodeIfPresent(WidgetRecommendationMirror.self, forKey: .executive)
        recoveryLabel = try c.decodeIfPresent(String.self, forKey: .recoveryLabel)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }
}

public enum WidgetKindContract {
    public static let all: [String] = [
        "LookAfter.Recommendation",
        "LookAfter.Today",
        "LookAfter.Focus",
        "LookAfter.Health",
        "LookAfter.Capture",
        "LookAfter.Medication",
        "LookAfter.Calendar",
        "LookAfter.Habits",
        "LookAfter.LifeState",
        "LookAfter.Brain",
        "LookAfter.Weekly",
        "LookAfter.Memory",
        "NowWidget",
        "EnergyWidget",
        "TasksWidget"
    ]
}

public enum WidgetDeepLinkContract {
    public static let scheme = "lookafter"
    public static func url(_ host: String) -> URL {
        URL(string: "\(scheme)://\(host)")!
    }
    public static func capture(mode: String) -> URL {
        URL(string: "\(scheme)://capture?mode=\(mode)")!
    }
    public static func task(id: String) -> URL {
        URL(string: "\(scheme)://task/\(id)")!
    }
}

public enum WidgetAppGroupContract {
    public static let identifier = "group.com.samaksh.flowos"
    public static let snapshotKey = "flowos.widget.snapshot"
    public static let commandQueueKey = "lookafter.widget.commands"
}
