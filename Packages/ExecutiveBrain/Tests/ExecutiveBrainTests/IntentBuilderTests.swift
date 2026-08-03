import XCTest
@testable import ExecutiveBrain
import LookAfterCore

final class IntentBuilderTests: XCTestCase {

    func testHealthKitIntentDescribesFutureNotUI() {
        let task = LifeTask(title: "HealthKit Integration", estimatedMinutes: 18)
        var world = WorldState()
        world.currentMission = task

        let semantics = SemanticDecisionBuilder.from(task: task)
        let intent = IntentBuilder().build(
            world: world,
            reasoning: ReasoningTrace(conclusions: ["Remove today's biggest blocker"]),
            semantics: semantics,
            heroTask: task,
            expectedOutcome: "",
            confidence: 0.93
        )

        XCTAssertTrue(intent.futureState.lowercased().contains("health"))
        XCTAssertFalse(intent.futureState.lowercased().contains("button"))
        XCTAssertEqual(intent.expectedCostReduction.restartTax, -45)
        XCTAssertEqual(intent.autonomyLevel, .userConfirmation)
    }

    func testSimulationEngineProducesChosenAndAlternative() {
        let task = LifeTask(title: "HealthKit Integration", estimatedMinutes: 18)
        let light = LifeTask(title: "Reply to email", estimatedMinutes: 10)
        var world = WorldState()
        world.currentMission = task
        world.topTasks = [task, light]

        let semantics = SemanticDecisionBuilder.from(task: task)
        let intent = IntentBuilder().build(
            world: world,
            reasoning: ReasoningTrace(),
            semantics: semantics,
            heroTask: task,
            expectedOutcome: "Sleep data available",
            confidence: 0.9
        )

        let sims = SimulationEngine().simulate(
            chosen: intent,
            world: world,
            reasoning: ReasoningTrace(),
            alternatives: [],
            heroTask: task
        )

        XCTAssertGreaterThanOrEqual(sims.count, 2)
        XCTAssertTrue(sims.contains { $0.wasChosen })
    }
}
