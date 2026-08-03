import XCTest
@testable import LifeOSCore

final class FlowConfidenceEngineTests: XCTestCase {

    private let engine = FlowConfidenceEngine()

    func testFullSignalsHighConfidence() {
        let task = FlowSchedulingTestFixtures.task(title: "Focus", status: .inProgress)
        let input = FlowSchedulingTestFixtures.input(tasks: [task])
        let scheduling = FlowSchedulingEngine(calendar: FlowSchedulingTestFixtures.calendar).schedule(from: input)
        let assessment = engine.assess(FlowConfidenceInput(
            directorInput: input,
            scheduling: scheduling,
            signalAvailability: EnvironmentSignalAvailability(
                health: true, calendar: true, weather: true, device: true, time: true
            )
        ))

        XCTAssertGreaterThan(assessment.overallScore, 0.85)
    }

    func testMissingHealthAndCalendarReduceConfidence() {
        let task = FlowSchedulingTestFixtures.task(title: "Focus")
        let input = FlowSchedulingTestFixtures.input(tasks: [task])
        let scheduling = FlowSchedulingEngine(calendar: FlowSchedulingTestFixtures.calendar).schedule(from: input)
        let assessment = engine.assess(FlowConfidenceInput(
            directorInput: input,
            scheduling: scheduling,
            signalAvailability: EnvironmentSignalAvailability(health: false, calendar: false)
        ))

        XCTAssertLessThan(assessment.overallScore, 0.85)
        XCTAssertTrue(assessment.penalties.contains { $0.reason.contains("health") })
        XCTAssertTrue(assessment.penalties.contains { $0.reason.contains("calendar") })
    }

    func testStaleBehaviorMemoryPenalty() {
        let task = FlowSchedulingTestFixtures.task(title: "Focus")
        let staleDate = FlowSchedulingTestFixtures.morningDate.addingTimeInterval(-72 * 3600)
        let behavior = BehaviorMemorySnapshot(
            recordedEventCount: 10,
            updatedAt: staleDate
        )
        let input = FlowSchedulingTestFixtures.input(tasks: [task], behavior: behavior)
        let scheduling = FlowSchedulingEngine(calendar: FlowSchedulingTestFixtures.calendar).schedule(from: input)
        let assessment = engine.assess(FlowConfidenceInput(
            directorInput: input,
            scheduling: scheduling,
            signalAvailability: EnvironmentSignalAvailability(health: true, calendar: true, device: true, time: true)
        ))

        XCTAssertTrue(assessment.penalties.contains { $0.reason.contains("Stale") })
    }

    func testConflictingSignalsPenalty() {
        let env = EnvironmentContext(
            energyScore: 0.85,
            hrvDelta: -0.2,
            sleepQuality: .poor,
            timeOfDay: .morning
        )
        let input = FlowSchedulingTestFixtures.input(
            tasks: [FlowSchedulingTestFixtures.task(title: "Work")],
            environment: env
        )
        let scheduling = FlowSchedulingEngine(calendar: FlowSchedulingTestFixtures.calendar).schedule(from: input)
        let assessment = engine.assess(FlowConfidenceInput(
            directorInput: input,
            scheduling: scheduling,
            signalAvailability: EnvironmentSignalAvailability(health: true, calendar: true, time: true)
        ))

        XCTAssertTrue(assessment.penalties.contains { $0.reason.contains("Conflicting") })
    }
}

final class FlowSurfaceBuilderTests: XCTestCase {

    func testBuilderMergesAllInputs() {
        let task = FlowSchedulingTestFixtures.task(title: "Design")
        let scheduling = FlowSchedulingResult(
            heroTask: task,
            prediction: FlowPrediction(
                taskID: task.id,
                suggestedDurationMinutes: 25,
                buttonLabel: "Start",
                buttonSubtitle: "25 min",
                confidence: 0,
                reasoning: "Good window.",
                actionType: .start
            ),
            flowPersonality: .steady,
            energyScore: 0.55,
            focusReadiness: 0.6
        )
        let confidence = FlowConfidenceAssessment(overallScore: 0.82)
        let surface = FlowSurfaceBuilder.build(from: FlowSurfaceBuildInput(
            scheduling: scheduling,
            briefing: FlowBriefingCopy(greeting: "Good afternoon.", briefingLines: ["Steady pace."]),
            behaviorMemory: BehaviorMemorySnapshot(recordedEventCount: 12),
            environmentContext: EnvironmentContext(energyScore: 0.55, isLowPowerMode: true),
            confidence: confidence,
            generatedAt: FlowSchedulingTestFixtures.morningDate
        ))

        XCTAssertEqual(surface.greeting, "Good afternoon.")
        XCTAssertEqual(surface.confidence, 0.82, accuracy: 0.001)
        XCTAssertEqual(surface.prediction?.confidence ?? 0, 0.82, accuracy: 0.001)
        XCTAssertLessThan(surface.focusReadiness, 0.6)
    }
}
