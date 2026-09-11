import XCTest
@testable import LookAfterFeatures
import LookAfterCore
import ExecutiveBrain

final class BriefingProjectorTests: XCTestCase {
    @MainActor
    func testHeroPriorityPrefersOrchestratorHero() {
        let hero = HeroBriefing(
            greeting: "Good morning",
            actionLine: "Ship the feature",
            supportingLine: "Momentum matters",
            outcomeLine: "You'll feel done",
            whyNowReasons: ["Best window now"],
            buttonLabel: "Start",
            action: ContextAction(label: "Start", taskID: "task-1", kind: .startTask),
            durationEstimate: DurationEstimate(pointMinutes: 25)
        )

        let surface = BriefingProjector.project(
            BriefingProjectorInput(
                userName: "Sam",
                heroBriefing: hero,
                recommendation: "Fallback"
            )
        )

        XCTAssertEqual(surface.executiveHero?.actionLine, "Ship the feature")
        XCTAssertEqual(surface.greeting.timeGreeting, "Good morning")
    }

    @MainActor
    func testHeroDisplayContentFallsBackToTopTask() {
        let task = LifeTask(title: "Write report", userId: "user-1")
        let display = BriefingProjector.heroDisplayContent(
            from: BriefingProjectorInput(
                userName: "Sam",
                topTasks: [task]
            )
        )

        XCTAssertFalse(display.title.isEmpty)
        XCTAssertEqual(display.buttonLabel, display.title)
    }
}
