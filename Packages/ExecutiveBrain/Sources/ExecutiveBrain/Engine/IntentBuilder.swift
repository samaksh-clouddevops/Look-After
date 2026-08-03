import Foundation
import LookAfterCore

/// Builds future-oriented intent from world model + reasoning — never UI copy.
public struct IntentBuilder: Sendable {

    public init() {}

    public func build(
        world: WorldState,
        reasoning: ReasoningTrace,
        semantics: SemanticDecision,
        heroTask: LifeTask?,
        expectedOutcome: String,
        confidence: Double
    ) -> ExecutiveIntent {
        let intervention = interventionLabel(task: heroTask, semantics: semantics)
        let futureState = inferFutureState(task: heroTask, semantics: semantics, world: world)
        let intention = inferIntention(world: world, reasoning: reasoning, semantics: semantics)
        let outcome = expectedOutcome.isEmpty
            ? inferExpectedOutcome(semantics: semantics, world: world)
            : expectedOutcome
        let costDelta = estimateCostReduction(task: heroTask, semantics: semantics, world: world)
        let reversibility = estimateReversibility(semantics: semantics, world: world)

        return ExecutiveIntent(
            futureState: futureState,
            intention: intention,
            intervention: intervention,
            expectedOutcome: outcome,
            expectedCostReduction: costDelta,
            confidence: confidence,
            reversibility: reversibility,
            autonomyLevel: .userConfirmation,
            semantics: semantics,
            taskID: heroTask?.id
        )
    }

    // MARK: - Future states

    private func inferFutureState(task: LifeTask?, semantics: SemanticDecision, world: WorldState) -> String {
        switch semantics.object.kind {
        case .appleHealthIntegration:
            return "Health tracking fully operational"
        case .oauthSignIn:
            return "Sign-in flow production-ready"
        case .shopping:
            return "Shopping list cleared"
        case .dayPlan:
            return "Day mapped with realistic blocks"
        case .startWork:
            return "Work session underway"
        default:
            if let task, task.isOverdue {
                return "Overdue weight lifted"
            }
            if world.isInFlowSession {
                return "Current work stream completed"
            }
            return task.map { "\($0.title) completed" } ?? "Next blocker removed"
        }
    }

    private func inferIntention(world: WorldState, reasoning: ReasoningTrace, semantics: SemanticDecision) -> String {
        if let conclusion = reasoning.conclusions.first, !conclusion.isEmpty {
            return conclusion
        }

        switch semantics.object.kind {
        case .appleHealthIntegration:
            return "Remove today's biggest blocker"
        case .shopping:
            return "Clear household friction before the day fills up"
        default:
            if world.minutesUntilNextEvent != nil, (world.minutesUntilNextEvent ?? 999) <= 90 {
                return "Use the open window before the calendar closes"
            }
            return "Move toward the most valuable future with available energy"
        }
    }

    private func inferExpectedOutcome(semantics: SemanticDecision, world: WorldState) -> String {
        switch semantics.object.kind {
        case .appleHealthIntegration:
            return "Sleep, medication, and recovery become available today"
        case .oauthSignIn:
            return "Users can sign in safely without you revisiting this"
        case .shopping:
            return "Groceries handled — one less mental tab open"
        default:
            if world.unpaidBillsCount > 0 {
                return "Financial stress stays contained"
            }
            return "Afternoon stays lighter after this is done"
        }
    }

    private func interventionLabel(task: LifeTask?, semantics: SemanticDecision) -> String {
        if let task {
            return HumanLanguage.outcomeHeadline(task: task)
        }
        return HumanLanguage.render(semantics).headline
    }

    private func estimateCostReduction(
        task: LifeTask?,
        semantics: SemanticDecision,
        world: WorldState
    ) -> ExecutiveCostDelta {
        var delta = ExecutiveCostDelta()

        switch semantics.object.kind {
        case .appleHealthIntegration:
            delta.restartTax = -45
            delta.stress = -18
        case .shopping:
            delta.stress = -12
            delta.restartTax = -10
        default:
            delta.restartTax = -Double(min(semantics.estimateMinutes, 30))
            delta.stress = task?.isOverdue == true ? -15 : -8
        }

        if world.isInFlowSession {
            delta.restartTax += 20
        }

        return delta
    }

    private func estimateReversibility(semantics: SemanticDecision, world: WorldState) -> Double {
        if semantics.object.kind == .appleHealthIntegration { return 0.9 }
        if world.isInFlowSession { return 0.3 }
        return 0.75
    }
}
