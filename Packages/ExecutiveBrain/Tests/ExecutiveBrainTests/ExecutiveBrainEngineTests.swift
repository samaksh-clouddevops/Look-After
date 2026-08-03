import XCTest
@testable import ExecutiveBrain
import LifeOSCore

final class ExecutiveBrainEngineTests: XCTestCase {

    func testReasoningPoorSleepShortWindowDefersDeepWork() {
        var environment = EnvironmentContext.baseline
        environment.nextEvent = CalendarEventReference(
            id: "1",
            title: "Team standup",
            startDate: Date().addingTimeInterval(45 * 60),
            endDate: Date().addingTimeInterval(75 * 60),
            minutesUntilStart: 45
        )
        environment.freeBlockMinutes = 45

        let task = LifeTask(title: "Search API refactor", estimatedMinutes: 90)
        let snapshot = ContextEngine().calculate(ContextEngineInput(
            cognitiveSnapshot: CognitiveSnapshot(energyScore: 0.35, availableMinutes: 45),
            environment: environment,
            heroTask: task,
            topTasks: [task]
        ))

        var medComponents = DateComponents()
        medComponents.hour = 7
        medComponents.minute = 30
        let thyroid = Medication(
            name: "Levothyroxine",
            dosage: "50mcg",
            scheduledTime: Calendar.current.date(from: medComponents)!,
            isTaken: false
        )

        let input = BrainTickInput(
            snapshot: snapshot,
            healthSummary: {
                var h = HealthSummary()
                h.totalSleepMinutes = 5 * 60 + 12
                return h
            }(),
            medications: [thyroid],
            tasks: [task],
            now: {
                var c = DateComponents()
                c.year = 2026; c.month = 8; c.day = 1
                c.hour = 8; c.minute = 30
                return Calendar.current.date(from: c)!
            }()
        )

        let state = ExecutiveBrainEngine().tick(input)

        XCTAssertFalse(state.decision.reasoning.conclusions.isEmpty)
        let joined = state.decision.reasoning.conclusions.joined(separator: " ").lowercased()
        XCTAssertTrue(joined.contains("small") || joined.contains("light") || joined.contains("log") || joined.contains("levothyroxine"))

        for conclusion in state.decision.reasoning.conclusions {
            XCTAssertFalse(conclusion.lowercased().contains("this evening"))
        }
    }

    func testBrainStateIncludesStructuredDecision() {
        let task = LifeTask(title: "Start Work", estimatedMinutes: 20)
        let snapshot = ContextEngine().calculate(ContextEngineInput(
            environment: .baseline,
            heroTask: task,
            topTasks: [task]
        ))

        let state = ExecutiveBrainEngine().tick(BrainTickInput(snapshot: snapshot, tasks: [task]))

        XCTAssertGreaterThan(state.decision.confidence, 0)
        XCTAssertFalse(state.decision.headline.isEmpty)
        XCTAssertFalse(state.decision.primaryAction.label.isEmpty)
        XCTAssertNotNil(state.hero)
    }

    func testDayPlanIncludesMedicationFromSchedule() {
        var components = DateComponents()
        components.hour = 9
        components.minute = 0
        let scheduled = Calendar.current.date(from: components)!
        let med = Medication(name: "Vitamin D", dosage: "1000 IU", scheduledTime: scheduled)

        var nowComponents = DateComponents()
        nowComponents.year = 2026
        nowComponents.month = 8
        nowComponents.day = 1
        nowComponents.hour = 9
        nowComponents.minute = 10
        let now = Calendar.current.date(from: nowComponents)!

        let snapshot = LifeContextSnapshot()
        let input = BrainTickInput(snapshot: snapshot, medications: [med], now: now)
        let state = ExecutiveBrainEngine().tick(input)

        XCTAssertTrue(state.plan.blocks.contains { $0.kind == .medication && $0.title == "Vitamin D" })
    }
}
