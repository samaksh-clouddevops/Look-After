import Foundation

public enum ValidationLayer: String, Codable, Sendable, CaseIterable {
    case staticValidation = "L1"
    case functional = "L2"
    case decision = "L3"
    case realityReplay = "L4-R"
    case syntheticSimulation = "L4-S"
    case learning = "L5"
    case executiveCost = "L6"
    case trust = "L7"
    case crossCutting = "Cross"

    public var displayName: String {
        switch self {
        case .staticValidation: return "Static"
        case .functional: return "Functional"
        case .decision: return "Decision"
        case .realityReplay: return "Reality Replay"
        case .syntheticSimulation: return "Synthetic Simulation"
        case .learning: return "Learning"
        case .executiveCost: return "Executive Cost"
        case .trust: return "Trust"
        case .crossCutting: return "Cross-cutting"
        }
    }
}

public enum AutomationStatus: String, Codable, Sendable {
    case automated
    case scaffold
    case notImplemented = "not_implemented"
    case manual
}

public enum TestStatus: String, Codable, Sendable {
    case pass
    case fail
    case skip
    case notImplemented = "not_implemented"
    case error
}

public struct QARequirement: Codable, Sendable, Identifiable {
    public var id: String
    public var sourceDocument: String
    public var validationLayer: ValidationLayer
    public var priority: String?
    public var title: String?
    public var automationStatus: AutomationStatus
    public var lastResult: TestResult?

    public init(
        id: String,
        sourceDocument: String,
        validationLayer: ValidationLayer,
        priority: String? = nil,
        title: String? = nil,
        automationStatus: AutomationStatus = .manual,
        lastResult: TestResult? = nil
    ) {
        self.id = id
        self.sourceDocument = sourceDocument
        self.validationLayer = validationLayer
        self.priority = priority
        self.title = title
        self.automationStatus = automationStatus
        self.lastResult = lastResult
    }
}

public struct TestResult: Codable, Sendable {
    public var requirementId: String
    public var sourceDocument: String
    public var validationLayer: ValidationLayer
    public var status: TestStatus
    public var durationMs: Int
    public var evidence: [String]
    public var message: String?

    public init(
        requirementId: String,
        sourceDocument: String,
        validationLayer: ValidationLayer,
        status: TestStatus,
        durationMs: Int = 0,
        evidence: [String] = [],
        message: String? = nil
    ) {
        self.requirementId = requirementId
        self.sourceDocument = sourceDocument
        self.validationLayer = validationLayer
        self.status = status
        self.durationMs = durationMs
        self.evidence = evidence
        self.message = message
    }
}

public struct DecisionRecord: Codable, Sendable {
    public var requirementId: String
    public var sourceDocument: String
    public var timestamp: Date
    public var inputFixture: String
    public var issuedIntent: String
    public var expectedIntent: String
    public var matchScore: Double
    public var totalBurden: Double?
}

public struct VersionComparisonReport: Codable, Sendable {
    public var question: String
    public var evidence: VersionEvidence
    public var verdict: String
    public var sourceDocuments: [String]
}

public struct VersionEvidence: Codable, Sendable {
    public var realityReplayWeeks: Int
    public var decisionsEvaluated: Int
    public var betterOutcomesPct: Double
    public var avgExecutiveCostDelta: Double
    public var trustDelta: Double
    public var satisfactionAcceptRateDelta: Double
    public var regressions: [String]
}

public struct RTMIndex: Codable, Sendable {
    public var generatedAt: Date
    public var requirements: [QARequirement]
    public var countsByLayer: [String: Int]
    public var northStarQuestion: String
}

public struct EVPRunSummary: Codable, Sendable {
    public var command: String
    public var startedAt: Date
    public var finishedAt: Date
    public var results: [TestResult]
    public var passed: Int
    public var failed: Int
    public var skipped: Int

    public var success: Bool { failed == 0 }
}
