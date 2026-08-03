import Foundation
import LookAfterCore

/// Deterministic explanations from reasoning — LLM may enrich later, never decide.
public struct ExplanationBuilder: Sendable {
    public init() {}

    public func explain(decision: BrainDecision) -> [String] {
        var lines: [String] = []
        lines.append(contentsOf: decision.reasoning.conclusions)
        if !decision.expectedOutcome.isEmpty {
            lines.append("Expected: \(decision.expectedOutcome)")
        }
        return lines
    }

    public func heroContextLine(decision: BrainDecision, world: WorldState) -> String? {
        if let first = decision.reasoning.conclusions.first {
            return first
        }
        if let mins = world.minutesUntilNextEvent, let event = world.nextEventTitle, mins <= 120 {
            return "You have \(mins) minutes before \(event)."
        }
        return decision.whyNow.first
    }
}
