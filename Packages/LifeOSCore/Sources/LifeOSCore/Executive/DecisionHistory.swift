import Foundation

/// What happened after the Brain issued an intent.
public enum DecisionDisposition: String, Codable, Sendable, CaseIterable {
    case pending
    case accepted
    case ignored
    case deferred
    case completed
}

public struct DecisionResult: Codable, Sendable, Equatable {
    public var recordedAt: Date
    public var actualMinutes: Int?
    public var completed: Bool
    public var ignoreReason: String?

    public init(
        recordedAt: Date = Date(),
        actualMinutes: Int? = nil,
        completed: Bool = false,
        ignoreReason: String? = nil
    ) {
        self.recordedAt = recordedAt
        self.actualMinutes = actualMinutes
        self.completed = completed
        self.ignoreReason = ignoreReason
    }
}

/// Policy learning — not episodic memory.
public struct PolicyLesson: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var pattern: String
    public var policy: String
    public var confidenceAdjustment: Double

    public init(
        id: String = UUID().uuidString,
        pattern: String,
        policy: String,
        confidenceAdjustment: Double = 0
    ) {
        self.id = id
        self.pattern = pattern
        self.policy = policy
        self.confidenceAdjustment = confidenceAdjustment
    }
}

/// Decision → Result → Lesson chain for policy learning.
public struct DecisionRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var issuedAt: Date
    public var intent: ExecutiveIntent
    public var reasoningSummary: String
    public var factorCount: Int
    public var simulations: [PlanSimulation]
    public var disposition: DecisionDisposition
    public var result: DecisionResult?
    public var lesson: PolicyLesson?

    public init(
        id: String = UUID().uuidString,
        issuedAt: Date = Date(),
        intent: ExecutiveIntent,
        reasoningSummary: String,
        factorCount: Int,
        simulations: [PlanSimulation] = [],
        disposition: DecisionDisposition = .pending,
        result: DecisionResult? = nil,
        lesson: PolicyLesson? = nil
    ) {
        self.id = id
        self.issuedAt = issuedAt
        self.intent = intent
        self.reasoningSummary = reasoningSummary
        self.factorCount = factorCount
        self.simulations = simulations
        self.disposition = disposition
        self.result = result
        self.lesson = lesson
    }
}
