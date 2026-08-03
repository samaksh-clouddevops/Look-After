import Foundation
import LifeOSCore

/// The Executive Brain — Chief of Staff, not chatbot.
///
/// Pipeline:
///   Signals → World Model → Reasoning → Planner → Decision → Explanation → UI
///
/// The LLM is NOT in this pipeline. It explains and converses elsewhere.
public struct ExecutiveBrainEngine: Sendable {
    private let worldStateBuilder: WorldStateBuilder
    private let reasoningEngine: ReasoningEngine
    private let decisionEngine: DecisionEngine
    private let planningEngine: PlanningEngine
    private let explanationBuilder: ExplanationBuilder
    private let historyStore: DecisionHistoryStore

    public init(
        worldStateBuilder: WorldStateBuilder = WorldStateBuilder(),
        reasoningEngine: ReasoningEngine = ReasoningEngine(),
        decisionEngine: DecisionEngine = DecisionEngine(),
        planningEngine: PlanningEngine = PlanningEngine(),
        explanationBuilder: ExplanationBuilder = ExplanationBuilder(),
        historyStore: DecisionHistoryStore = .shared
    ) {
        self.worldStateBuilder = worldStateBuilder
        self.reasoningEngine = reasoningEngine
        self.decisionEngine = decisionEngine
        self.planningEngine = planningEngine
        self.explanationBuilder = explanationBuilder
        self.historyStore = historyStore
    }

    /// One reasoning tick — called on every context refresh and life change.
    public func tick(_ input: BrainTickInput) -> BrainState {
        let world = worldStateBuilder.build(from: input)
        let reasoning = reasoningEngine.reason(over: world, now: input.now)
        let (decision, briefing) = decisionEngine.decide(world: world, reasoning: reasoning, input: input)
        let plan = planningEngine.plan(
            world: world,
            reasoning: reasoning,
            timelineItems: input.timelineItems,
            now: input.now
        )

        _ = explanationBuilder.explain(decision: decision)

        historyStore.recordIssued(
            intent: decision.intent,
            reasoning: reasoning,
            simulations: decision.simulations
        )

        return BrainState(
            world: world,
            decision: decision,
            plan: plan,
            briefing: briefing,
            snapshot: input.snapshot,
            generatedAt: input.now
        )
    }
}
