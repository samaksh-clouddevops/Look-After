import Foundation
import LifeOSCore

/// A structured decision — never an LLM blob.
public struct BrainDecision: Codable, Sendable, Equatable {
    /// Future the Brain is steering toward — source of truth.
    public var intent: ExecutiveIntent
    /// Candidate futures that were simulated.
    public var simulations: [PlanSimulation]
    /// Rendering bridge — legacy; prefer IntentRenderer.
    public var semantics: SemanticDecision
    public var primaryAction: ContextAction
    public var headline: String
    public var supportingLine: String
    public var whyNow: [String]
    public var confidence: Double
    public var confidenceLevel: RecommendationConfidenceLevel
    public var expectedOutcome: String
    public var alternatives: [BrainAlternative]
    public var reasoning: ReasoningTrace
    public var durationEstimate: DurationEstimate
    public var insights: [RecommendationInsight]

    public init(
        intent: ExecutiveIntent,
        simulations: [PlanSimulation] = [],
        semantics: SemanticDecision,
        primaryAction: ContextAction,
        headline: String,
        supportingLine: String,
        whyNow: [String],
        confidence: Double,
        confidenceLevel: RecommendationConfidenceLevel,
        expectedOutcome: String,
        alternatives: [BrainAlternative] = [],
        reasoning: ReasoningTrace,
        durationEstimate: DurationEstimate,
        insights: [RecommendationInsight] = []
    ) {
        self.intent = intent
        self.simulations = simulations
        self.semantics = semantics
        self.primaryAction = primaryAction
        self.headline = headline
        self.supportingLine = supportingLine
        self.whyNow = whyNow
        self.confidence = min(max(confidence, 0), 1)
        self.confidenceLevel = confidenceLevel
        self.expectedOutcome = expectedOutcome
        self.alternatives = alternatives
        self.reasoning = reasoning
        self.durationEstimate = durationEstimate
        self.insights = insights
    }
}

public struct BrainAlternative: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var action: ContextAction
    public var reason: String

    public init(
        id: String = UUID().uuidString,
        label: String,
        action: ContextAction,
        reason: String
    ) {
        self.id = id
        self.label = label
        self.action = action
        self.reason = reason
    }
}
