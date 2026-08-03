import Foundation

public enum CyclePhase: String, Codable, Sendable, CaseIterable {
    case menstrual
    case follicular
    case ovulation
    case luteal
    case unknown

    public var displayLabel: String {
        switch self {
        case .menstrual: return "Menstrual"
        case .follicular: return "Follicular"
        case .ovulation: return "Ovulation"
        case .luteal: return "Luteal"
        case .unknown: return "Learning"
        }
    }
}

public enum CycleFlowLevel: String, Codable, Sendable, CaseIterable {
    case none
    case spotting
    case light
    case medium
    case heavy

    public var displayLabel: String {
        switch self {
        case .none: return "None"
        case .spotting: return "Spotting"
        case .light: return "Light"
        case .medium: return "Medium"
        case .heavy: return "Heavy"
        }
    }
}

public enum CycleLogSource: String, Codable, Sendable {
    case manual
    case healthKit
}

public enum CycleInsightActionKind: String, Codable, Sendable {
    case protectEnergy
    case logSymptom
    case adjustPlan
    case recoveryMode
    case none
}

public struct CycleTrackingPreferences: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var averageCycleLengthDays: Int
    public var averagePeriodLengthDays: Int
    public var lastPeriodStart: Date?
    public var usesHealthKit: Bool
    public var commonSymptoms: [String]

    public static let `default` = CycleTrackingPreferences(
        isEnabled: false,
        averageCycleLengthDays: 28,
        averagePeriodLengthDays: 5,
        lastPeriodStart: nil,
        usesHealthKit: true,
        commonSymptoms: []
    )

    public init(
        isEnabled: Bool = false,
        averageCycleLengthDays: Int = 28,
        averagePeriodLengthDays: Int = 5,
        lastPeriodStart: Date? = nil,
        usesHealthKit: Bool = true,
        commonSymptoms: [String] = []
    ) {
        self.isEnabled = isEnabled
        self.averageCycleLengthDays = min(max(averageCycleLengthDays, 21), 45)
        self.averagePeriodLengthDays = min(max(averagePeriodLengthDays, 2), 10)
        self.lastPeriodStart = lastPeriodStart
        self.usesHealthKit = usesHealthKit
        self.commonSymptoms = commonSymptoms
    }
}

public struct CycleDayLog: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var day: Date
    public var flow: CycleFlowLevel?
    public var symptoms: [String]
    public var mood: String?
    public var energy: Int?
    public var notes: String?
    public var source: CycleLogSource

    public init(
        id: String = UUID().uuidString,
        day: Date,
        flow: CycleFlowLevel? = nil,
        symptoms: [String] = [],
        mood: String? = nil,
        energy: Int? = nil,
        notes: String? = nil,
        source: CycleLogSource = .manual
    ) {
        self.id = id
        self.day = day
        self.flow = flow
        self.symptoms = symptoms
        self.mood = mood
        self.energy = energy.map { min(max($0, 1), 5) }
        self.notes = notes
        self.source = source
    }
}

public enum CycleConfidence: String, Codable, Sendable {
    case low
    case medium
    case high
}

public struct CycleSnapshot: Sendable, Equatable {
    public var cycleDay: Int?
    public var phase: CyclePhase
    public var daysUntilPeriod: Int?
    public var predictedPeriodStart: Date?
    public var confidence: CycleConfidence
    public var averageCycleLengthDays: Int
    public var averagePeriodLengthDays: Int
    public var isEnabled: Bool

    public static let disabled = CycleSnapshot(
        cycleDay: nil,
        phase: .unknown,
        daysUntilPeriod: nil,
        predictedPeriodStart: nil,
        confidence: .low,
        averageCycleLengthDays: 28,
        averagePeriodLengthDays: 5,
        isEnabled: false
    )

    public var phaseLabel: String {
        guard isEnabled else { return "" }
        if let day = cycleDay {
            return "Day \(day) · \(phase.displayLabel)"
        }
        return phase.displayLabel
    }

    public var periodCountdownLabel: String? {
        guard isEnabled, let days = daysUntilPeriod else { return nil }
        if days == 0 { return "Period may start today" }
        if days == 1 { return "Period in ~1 day" }
        return "Period in ~\(days) days"
    }
}

public struct CycleInsight: Sendable, Equatable, Identifiable {
    public let id: String
    public var headline: String
    public var body: String
    public var actionKind: CycleInsightActionKind
    public var priority: Int
    public var isAIGenerated: Bool

    public init(
        id: String = UUID().uuidString,
        headline: String,
        body: String,
        actionKind: CycleInsightActionKind = .none,
        priority: Int = 0,
        isAIGenerated: Bool = false
    ) {
        self.id = id
        self.headline = headline
        self.body = body
        self.actionKind = actionKind
        self.priority = priority
        self.isAIGenerated = isAIGenerated
    }
}

public enum CycleSymptomCatalog {
    public static let common: [String] = [
        "Cramps",
        "Fatigue",
        "Brain fog",
        "Mood swings",
        "Bloating",
        "Headache",
        "Insomnia",
        "Anxiety",
        "Low energy",
        "Cravings",
    ]
}
