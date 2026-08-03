import Foundation

/// How much autonomy the Brain has to act on this intent.
public enum AutonomyLevel: String, Codable, Sendable, CaseIterable {
    case automatic
    case userConfirmation
    case suggestionOnly
}

/// Describes the future the Brain is steering toward — not UI copy.
public struct ExecutiveIntent: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var futureState: String
    public var intention: String
    public var intervention: String
    public var expectedOutcome: String
    public var expectedCostReduction: ExecutiveCostDelta
    public var confidence: Double
    public var reversibility: Double
    public var autonomyLevel: AutonomyLevel
    /// Rendering bridge — expresses intervention, never decides.
    public var semantics: SemanticDecision
    public var taskID: String?
    public var generatedAt: Date

    public init(
        id: String = UUID().uuidString,
        futureState: String,
        intention: String,
        intervention: String,
        expectedOutcome: String,
        expectedCostReduction: ExecutiveCostDelta = ExecutiveCostDelta(),
        confidence: Double,
        reversibility: Double = 0.7,
        autonomyLevel: AutonomyLevel = .userConfirmation,
        semantics: SemanticDecision,
        taskID: String? = nil,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.futureState = futureState
        self.intention = intention
        self.intervention = intervention
        self.expectedOutcome = expectedOutcome
        self.expectedCostReduction = expectedCostReduction
        self.confidence = min(max(confidence, 0), 1)
        self.reversibility = min(max(reversibility, 0), 1)
        self.autonomyLevel = autonomyLevel
        self.semantics = semantics
        self.taskID = taskID
        self.generatedAt = generatedAt
    }
}

/// A candidate future the Brain simulated but did not choose.
public struct PlanSimulation: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var intent: ExecutiveIntent
    public var projectedCost: ExecutiveCost
    public var score: Double
    public var wasChosen: Bool

    public init(
        id: String = UUID().uuidString,
        label: String,
        intent: ExecutiveIntent,
        projectedCost: ExecutiveCost,
        score: Double,
        wasChosen: Bool = false
    ) {
        self.id = id
        self.label = label
        self.intent = intent
        self.projectedCost = projectedCost
        self.score = score
        self.wasChosen = wasChosen
    }
}
