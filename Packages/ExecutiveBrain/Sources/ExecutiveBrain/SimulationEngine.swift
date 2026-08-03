import Foundation
import LifeOSCore

/// Compares candidate futures — outputs inspectable simulations, not UI.
public struct SimulationEngine: Sendable {
    private let intentBuilder: IntentBuilder

    public init(intentBuilder: IntentBuilder = IntentBuilder()) {
        self.intentBuilder = intentBuilder
    }

    public func simulate(
        chosen: ExecutiveIntent,
        world: WorldState,
        reasoning: ReasoningTrace,
        alternatives: [BrainAlternative],
        heroTask: LifeTask?
    ) -> [PlanSimulation] {
        var results: [PlanSimulation] = []

        let chosenCost = projectCost(for: chosen, world: world)
        results.append(PlanSimulation(
            label: "Chosen",
            intent: chosen,
            projectedCost: chosenCost,
            score: score(cost: chosenCost, confidence: chosen.confidence),
            wasChosen: true
        ))

        if let altTask = world.topTasks.first(where: { $0.id != chosen.taskID && $0.estimatedMinutes <= 20 }) {
            let altSemantics = SemanticDecisionBuilder.from(task: altTask)
            let altIntent = intentBuilder.build(
                world: world,
                reasoning: reasoning,
                semantics: altSemantics,
                heroTask: altTask,
                expectedOutcome: "Lighter progress while energy is limited",
                confidence: max(chosen.confidence - 0.15, 0.4)
            )
            let altCost = projectCost(for: altIntent, world: world)
            results.append(PlanSimulation(
                label: "Simulation B — lighter",
                intent: altIntent,
                projectedCost: altCost,
                score: score(cost: altCost, confidence: altIntent.confidence),
                wasChosen: false
            ))
        } else if world.currentEnergy < 0.45 {
            let restSemantics = SemanticDecision(
                verb: .start,
                object: DecisionObject(kind: .genericTask, rawTitle: "Rest and eat"),
                benefit: .lighterDay,
                estimateMinutes: 15,
                confidence: 0.6
            )
            let restIntent = intentBuilder.build(
                world: world,
                reasoning: reasoning,
                semantics: restSemantics,
                heroTask: nil,
                expectedOutcome: "Energy recovers enough to attempt meaningful work",
                confidence: 0.55
            )
            let restCost = projectCost(for: restIntent, world: world)
            results.append(PlanSimulation(
                label: "Simulation B — recover",
                intent: restIntent,
                projectedCost: restCost,
                score: score(cost: restCost, confidence: restIntent.confidence),
                wasChosen: false
            ))
        }

        return results
    }

    private func projectCost(for intent: ExecutiveIntent, world: WorldState) -> ExecutiveCost {
        var base = ExecutiveCost(
            stress: world.cognitiveLoad == .overloaded ? 40 : 20,
            time: Double(intent.semantics.estimateMinutes),
            energy: (1 - world.currentEnergy) * 30,
            attention: 10,
            restartTax: world.isInFlowSession ? 35 : 15
        )

        let delta = intent.expectedCostReduction
        base.stress += delta.stress
        base.restartTax += delta.restartTax
        base.time += delta.time
        base.energy += delta.energy
        base.attention += delta.attention
        return base
    }

    private func score(cost: ExecutiveCost, confidence: Double) -> Double {
        max(0, (1 - cost.totalBurden / 200) * confidence)
    }
}
