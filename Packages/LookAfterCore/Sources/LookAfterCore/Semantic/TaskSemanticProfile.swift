import Foundation

// MARK: - Task meaning (Brain schedules from this — never from titles)

/// What the task *is*, independent of how the user phrased it.
public enum TaskSemanticType: String, Codable, Sendable, CaseIterable {
    case medication
    case deepWork
    case errand
    case physicalActivity
    case administrative
    case communication
    case creative
    case learning
    case selfCare
    case generic
}

public enum SchedulingConstraintKind: String, Codable, Sendable, CaseIterable {
    case beforeBreakfast
    case afterMealsForbidden
    case sameTimeDaily
    case requiresStoreOpen
    case requiresUninterruptedBlock
    case avoidAfterPoorSleep
    case requiresEmptyStomach
    case neverEveningDose
    case combineWithNearbyErrands
}

public enum TimeWindowPreference: String, Codable, Sendable, CaseIterable {
    case morning
    case midday
    case afternoon
    case evening
    case night
    case anytime

    /// Local hours this window covers. Night wraps midnight.
    public var hours: Set<Int> {
        switch self {
        case .morning: return Set(5..<11)
        case .midday: return Set(11..<14)
        case .afternoon: return Set(14..<17)
        case .evening: return Set(17..<21)
        case .night: return Set(21..<24).union(0..<5)
        case .anytime: return Set(0..<24)
        }
    }
}

public enum TaskFlexibility: String, Codable, Sendable, CaseIterable {
    case rigid
    case low
    case moderate
    case high
}

public enum SemanticEnergyRequirement: String, Codable, Sendable, CaseIterable {
    case minimal
    case low
    case moderate
    case high
    case peak
}

public enum CognitiveRequirement: String, Codable, Sendable, CaseIterable {
    case minimal
    case light
    case moderate
    case deepFocus
}

public enum ConsequenceOfDelay: String, Codable, Sendable, CaseIterable {
    case none
    case low
    case moderate
    case high
    case medicalRisk

    public var severity: Int {
        switch self {
        case .none: return 0
        case .low: return 1
        case .moderate: return 2
        case .high: return 3
        case .medicalRisk: return 4
        }
    }
}

public enum TaskSemanticSource: String, Codable, Sendable {
    case deterministic
    case llm
    case merged
}

/// Structured meaning of a task — computed once at create/edit, consumed by all schedulers.
public struct TaskSemanticProfile: Codable, Sendable, Equatable, Hashable {
    public var semanticType: TaskSemanticType
    public var subtype: String
    public var schedulingConstraints: [SchedulingConstraintKind]
    public var requiredConditions: [String]
    public var preferredTimeWindows: [TimeWindowPreference]
    public var forbiddenTimeWindows: [TimeWindowPreference]
    public var estimatedDuration: Int
    public var flexibility: TaskFlexibility
    public var splittable: Bool
    public var interruptionTolerance: Double
    public var energyRequirement: SemanticEnergyRequirement
    public var cognitiveRequirement: CognitiveRequirement
    public var locationRequirement: String?
    public var recurringRules: String?
    public var dependencies: [String]
    public var consequenceOfDelay: ConsequenceOfDelay
    public var confidence: Double
    public var analyzedAt: Date
    public var source: TaskSemanticSource

    public init(
        semanticType: TaskSemanticType,
        subtype: String = "",
        schedulingConstraints: [SchedulingConstraintKind] = [],
        requiredConditions: [String] = [],
        preferredTimeWindows: [TimeWindowPreference] = [.anytime],
        forbiddenTimeWindows: [TimeWindowPreference] = [],
        estimatedDuration: Int = 30,
        flexibility: TaskFlexibility = .moderate,
        splittable: Bool = true,
        interruptionTolerance: Double = 0.5,
        energyRequirement: SemanticEnergyRequirement = .moderate,
        cognitiveRequirement: CognitiveRequirement = .moderate,
        locationRequirement: String? = nil,
        recurringRules: String? = nil,
        dependencies: [String] = [],
        consequenceOfDelay: ConsequenceOfDelay = .low,
        confidence: Double = 0.7,
        analyzedAt: Date = Date(),
        source: TaskSemanticSource = .deterministic
    ) {
        self.semanticType = semanticType
        self.subtype = subtype
        self.schedulingConstraints = schedulingConstraints
        self.requiredConditions = requiredConditions
        self.preferredTimeWindows = preferredTimeWindows
        self.forbiddenTimeWindows = forbiddenTimeWindows
        self.estimatedDuration = max(1, estimatedDuration)
        self.flexibility = flexibility
        self.splittable = splittable
        self.interruptionTolerance = min(max(interruptionTolerance, 0), 1)
        self.energyRequirement = energyRequirement
        self.cognitiveRequirement = cognitiveRequirement
        self.locationRequirement = locationRequirement
        self.recurringRules = recurringRules
        self.dependencies = dependencies
        self.consequenceOfDelay = consequenceOfDelay
        self.confidence = min(max(confidence, 0), 1)
        self.analyzedAt = analyzedAt
        self.source = source
    }
}

public struct TaskSchedulabilityResult: Sendable, Equatable {
    public var isAllowed: Bool
    public var reason: String?

    public init(isAllowed: Bool, reason: String? = nil) {
        self.isAllowed = isAllowed
        self.reason = reason
    }
}

public extension LifeTask {
    /// Profile from storage, or a deterministic fallback for legacy tasks.
    var resolvedSemanticProfile: TaskSemanticProfile {
        TaskSemanticProfileBuilder.classificationProfile(for: self)
    }

    var needsSemanticAnalysis: Bool {
        semanticProfile == nil
    }

    func semanticFieldsChanged(comparedTo previous: LifeTask) -> Bool {
        title != previous.title
            || description != previous.description
            || lifeArea != previous.lifeArea
            || tags != previous.tags
            || difficulty != previous.difficulty
            || estimatedMinutes != previous.estimatedMinutes
            || recurrenceRule != previous.recurrenceRule
    }
}
