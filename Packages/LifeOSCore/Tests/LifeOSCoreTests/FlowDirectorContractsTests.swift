import XCTest
@testable import LifeOSCore

final class FlowDirectorContractsTests: XCTestCase {

    // MARK: - Flow Personality

    func testFlowPersonalityFromEnergyScore() {
        XCTAssertEqual(FlowPersonality.from(energyScore: 0.0), .restore)
        XCTAssertEqual(FlowPersonality.from(energyScore: 0.35), .restore)
        XCTAssertEqual(FlowPersonality.from(energyScore: 0.36), .steady)
        XCTAssertEqual(FlowPersonality.from(energyScore: 0.65), .steady)
        XCTAssertEqual(FlowPersonality.from(energyScore: 0.66), .peak)
        XCTAssertEqual(FlowPersonality.from(energyScore: 1.0), .peak)
    }

    func testFlowPersonalityClampsOutOfRangeInput() {
        XCTAssertEqual(FlowPersonality.from(energyScore: -1), .restore)
        XCTAssertEqual(FlowPersonality.from(energyScore: 2), .peak)
    }

    // MARK: - Codable Round-Trip

    func testFlowSurfaceCodableRoundTrip() throws {
        let task = LifeTask(title: "API Review", status: .inProgress, estimatedMinutes: 18)
        let prediction = FlowPrediction(
            taskID: task.id,
            suggestedDurationMinutes: 18,
            buttonLabel: "Continue API Review",
            buttonSubtitle: "18 minutes · Ready now",
            confidence: 0.92,
            reasoning: "In-progress task with matching energy.",
            actionType: .continue
        )
        let surface = FlowSurface(
            greeting: "Good morning, Sam.",
            briefingLines: ["Your HRV is higher than usual."],
            flowPersonality: .peak,
            heroTask: task,
            prediction: prediction,
            energyScore: 0.78,
            focusReadiness: 0.85,
            confidence: 0.9
        )

        let data = try JSONEncoder().encode(surface)
        let decoded = try JSONDecoder().decode(FlowSurface.self, from: data)

        XCTAssertEqual(decoded.greeting, surface.greeting)
        XCTAssertEqual(decoded.heroTask?.title, task.title)
        XCTAssertEqual(decoded.prediction?.actionType, .continue)
        XCTAssertEqual(decoded.flowPersonality, FlowPersonality.peak)
    }

    func testFlowDirectorInputCodableRoundTrip() throws {
        let input = FlowDirectorInput(
            cognitiveSnapshot: CognitiveSnapshot(energyScore: 0.7),
            pendingTasks: [LifeTask(title: "Write docs")],
            behaviorMemory: .empty,
            environmentContext: .baseline,
            userName: "Sam"
        )

        let data = try JSONEncoder().encode(input)
        let decoded = try JSONDecoder().decode(FlowDirectorInput.self, from: data)

        XCTAssertEqual(decoded.userName, "Sam")
        XCTAssertEqual(decoded.pendingTasks.count, 1)
    }

    func testEnvironmentContextCodableRoundTrip() throws {
        let event = CalendarEventReference(
            id: "evt-1",
            title: "Team Sync",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            minutesUntilStart: 45
        )
        var context = EnvironmentContext.baseline
        context.nextEvent = event
        context.weather = .rain

        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(EnvironmentContext.self, from: data)

        XCTAssertEqual(decoded.nextEvent?.title, "Team Sync")
        XCTAssertEqual(decoded.weather, .rain)
    }

    // MARK: - Flow Surface Builder

    func testFlowSurfaceBuilderMergesSchedulingAndBriefing() {
        let task = LifeTask(title: "Design")
        let scheduling = FlowSchedulingResult(
            heroTask: task,
            prediction: FlowPrediction(
                taskID: task.id,
                suggestedDurationMinutes: 25,
                buttonLabel: "Start Flow",
                buttonSubtitle: "25 minutes",
                confidence: 0.8,
                reasoning: "Good energy window.",
                actionType: .start
            ),
            flowPersonality: .steady,
            energyScore: 0.55,
            focusReadiness: 0.6,
            confidence: 0.8
        )
        let briefing = FlowBriefingCopy(
            greeting: "Good afternoon.",
            briefingLines: ["Steady pace today."]
        )

        let surface = FlowSurfaceBuilder.build(scheduling: scheduling, briefing: briefing)

        XCTAssertEqual(surface.greeting, "Good afternoon.")
        XCTAssertEqual(surface.briefingLines, ["Steady pace today."])
        XCTAssertEqual(surface.heroTask?.title, "Design")
        XCTAssertTrue(surface.hasHeroAction)
    }

    // MARK: - Behavior Memory

    func testBehaviorMemoryDeferralLookup() {
        let snapshot = BehaviorMemorySnapshot(
            deferralRecords: [
                TaskDeferralRecord(taskID: "task-a", deferralCount: 3)
            ]
        )
        XCTAssertEqual(snapshot.deferralCount(for: "task-a"), 3)
        XCTAssertEqual(snapshot.deferralCount(for: "task-b"), 0)
    }

    // MARK: - Time of Day

    func testTimeOfDayFromDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 31
        components.hour = 8
        components.minute = 42
        let morning = calendar.date(from: components)!

        components.hour = 14
        let afternoon = calendar.date(from: components)!

        components.hour = 22
        let night = calendar.date(from: components)!

        XCTAssertEqual(TimeOfDay.from(date: morning, calendar: calendar), .morning)
        XCTAssertEqual(TimeOfDay.from(date: afternoon, calendar: calendar), .afternoon)
        XCTAssertEqual(TimeOfDay.from(date: night, calendar: calendar), .night)
    }
}
