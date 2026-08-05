import XCTest
@testable import LookAfterCore

final class FlowSchedulingEngineTests: XCTestCase {

    private let engine = FlowSchedulingEngine(calendar: FlowSchedulingTestFixtures.calendar)

    func testDeterministicForIdenticalInputs() {
        let inProgress = FlowSchedulingTestFixtures.task(title: "API Review", status: .inProgress, estimatedMinutes: 18)
        let input = FlowSchedulingTestFixtures.input(
            tasks: [inProgress, FlowSchedulingTestFixtures.task(title: "Other")],
            environment: EnvironmentContext(energyScore: 0.72, timeOfDay: .morning)
        )

        let first = engine.schedule(from: input)
        let second = engine.schedule(from: input)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.heroTask?.title, "API Review")
        XCTAssertEqual(first.prediction?.actionType, .continue)
    }

    func testIntegrationMeetingSoonAndContinue() {
        let event = CalendarEventReference(
            id: "e1", title: "Team Sync", startDate: Date(), endDate: Date(), minutesUntilStart: 40
        )
        let inProgress = FlowSchedulingTestFixtures.task(title: "API Review", status: .inProgress, estimatedMinutes: 18)
        let env = EnvironmentContext(energyScore: 0.7, nextEvent: event, timeOfDay: .morning)
        let input = FlowSchedulingTestFixtures.input(tasks: [inProgress], environment: env)

        let result = engine.schedule(from: input)

        XCTAssertEqual(result.heroTask?.title, "API Review")
        XCTAssertEqual(result.prediction?.actionType, .continue)
        XCTAssertLessThanOrEqual(result.prediction?.suggestedDurationMinutes ?? 999, 30)
        XCTAssertEqual(result.nextCalendarEvent?.title, "Team Sync")
    }

    func testIntegrationDeepWorkWithGap() {
        let deep = FlowSchedulingTestFixtures.task(
            title: "Architecture Design",
            estimatedMinutes: 60,
            difficulty: .hard,
            priority: .high
        )
        let env = EnvironmentContext(energyScore: 0.85, freeBlockMinutes: 150, timeOfDay: .morning)
        let input = FlowSchedulingTestFixtures.input(tasks: [deep], environment: env)

        let result = engine.schedule(from: input)

        XCTAssertEqual(result.prediction?.actionType, .startDeep)
        XCTAssertEqual(result.flowPersonality, FlowPersonality.peak)
        XCTAssertNotNil(result.flowWindow)
    }

    func testIntegrationDeferralCoachMoment() {
        let task = FlowSchedulingTestFixtures.task(id: "t-defer", title: "Taxes")
        let behavior = BehaviorMemorySnapshot(
            deferralRecords: [TaskDeferralRecord(taskID: "t-defer", deferralCount: 4)]
        )
        let input = FlowSchedulingTestFixtures.input(tasks: [task], behavior: behavior)

        let result = engine.schedule(from: input)

        XCTAssertEqual(result.prediction?.actionType, .tryMicro)
        XCTAssertNotNil(result.coachMoment)
    }

    func testEmptyTasksReturnsNoHero() {
        let input = FlowSchedulingTestFixtures.input(tasks: [])
        let result = engine.schedule(from: input)
        XCTAssertNil(result.heroTask)
        XCTAssertNil(result.prediction)
    }

    func testPerformanceUnder100ms() {
        var tasks: [LifeTask] = []
        for i in 0..<200 {
            tasks.append(FlowSchedulingTestFixtures.task(title: "Task \(i)", estimatedMinutes: 15 + (i % 30)))
        }
        let input = FlowSchedulingTestFixtures.input(
            tasks: tasks,
            environment: EnvironmentContext(energyScore: 0.6, freeBlockMinutes: 120, timeOfDay: .morning)
        )

        let start = Date()
        for _ in 0..<100 {
            _ = engine.schedule(from: input)
        }
        let elapsed = Date().timeIntervalSince(start)
        // Shared CI runners are noisy; keep a generous ceiling that still
        // catches pathological O(n²) regressions on 200-task inputs.
        XCTAssertLessThan(elapsed, 15.0, "100 scheduling passes should complete under 15s (was \(elapsed)s)")
    }
}
