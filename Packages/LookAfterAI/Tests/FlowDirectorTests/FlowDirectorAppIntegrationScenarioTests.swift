import XCTest
@testable import LookAfterAI
import LookAfterCore

/// Validates realistic orchestration scenarios mirroring app-layer wiring.
final class FlowDirectorAppIntegrationScenarioTests: XCTestCase {

    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    private func fixedDate(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 31
        components.hour = hour
        return calendar.date(from: components)!
    }

    @MainActor
    private func makeDirector(
        environment: EnvironmentContext,
        availability: EnvironmentSignalAvailability
    ) -> (FlowDirector, MockBehaviorStore, MockEnvironmentSource) {
        let store = MockBehaviorStore()
        let env = MockEnvironmentSource(result: EnvironmentContextResult(
            context: environment,
            availability: availability
        ))
        let director = FlowDirector(
            behaviorStore: store,
            analysisEngine: MockAnalysisEngine(snapshot: .empty),
            environmentSource: env
        )
        return (director, store, env)
    }

    @MainActor
    func testScenarioHighEnergyMorningWithInProgressTask() async {
        let apiReview = LifeTask(title: "API Review", priority: .high, status: .inProgress, estimatedMinutes: 18)
        let email = LifeTask(title: "Reply to email", estimatedMinutes: 10)
        let env = EnvironmentContext(energyScore: 0.82, freeBlockMinutes: 120, timeOfDay: .morning)
        let (director, _, _) = makeDirector(
            environment: env,
            availability: EnvironmentSignalAvailability(health: true, calendar: true, device: true, time: true)
        )

        director.session = FlowDirectorSession(
            cognitiveSnapshot: CognitiveSnapshot(energyScore: 0.82, focusCapacity: 0.75),
            pendingTasks: [email, apiReview],
            currentTime: fixedDate(hour: 9),
            userName: "Sam"
        )
        await director.orchestrate()

        XCTAssertEqual(director.surface.heroTask?.title, "API Review")
        XCTAssertEqual(director.surface.prediction?.actionType, .continue)
        XCTAssertGreaterThan(director.surface.confidence, 0.7)
        print("[Scenario] Morning high energy → Continue API Review, confidence=\(director.surface.confidence)")
    }

    @MainActor
    func testScenarioMeetingSoonCapsDuration() async {
        let event = CalendarEventReference(
            id: "sync", title: "Team Sync",
            startDate: Date(), endDate: Date(), minutesUntilStart: 35
        )
        let longTask = LifeTask(title: "Architecture Design", difficulty: .hard, estimatedMinutes: 90)
        let shortTask = LifeTask(title: "Quick review", estimatedMinutes: 15)
        let env = EnvironmentContext(energyScore: 0.7, nextEvent: event, freeBlockMinutes: 30, timeOfDay: .morning)
        let (director, _, _) = makeDirector(
            environment: env,
            availability: EnvironmentSignalAvailability(health: true, calendar: true, time: true)
        )

        director.session = FlowDirectorSession(
            cognitiveSnapshot: CognitiveSnapshot(energyScore: 0.7),
            pendingTasks: [longTask, shortTask],
            currentTime: fixedDate(hour: 10),
            userName: "Sam"
        )
        await director.orchestrate()

        XCTAssertLessThanOrEqual(director.surface.prediction?.suggestedDurationMinutes ?? 999, 30)
        XCTAssertEqual(director.surface.nextCalendarEvent?.title, "Team Sync")
        print("[Scenario] Meeting in 35m → duration capped, event=\(director.surface.nextCalendarEvent?.title ?? "")")
    }

    @MainActor
    func testScenarioLowEnergyWithoutHealth() async {
        let hardTask = LifeTask(title: "Deep Design", difficulty: .hard, estimatedMinutes: 60, requiredEnergy: .peak)
        let easyTask = LifeTask(title: "Inbox sweep", difficulty: .easy, estimatedMinutes: 10)
        let env = EnvironmentContext(energyScore: 0.25, sleepQuality: .poor, timeOfDay: .morning)
        let (director, _, _) = makeDirector(
            environment: env,
            availability: EnvironmentSignalAvailability(health: false, calendar: false, time: true)
        )

        director.session = FlowDirectorSession(
            cognitiveSnapshot: CognitiveSnapshot(energyScore: 0.25, focusCapacity: 0.3),
            pendingTasks: [hardTask, easyTask],
            currentTime: fixedDate(hour: 9),
            userName: "Sam"
        )
        await director.orchestrate()

        XCTAssertEqual(director.surface.flowPersonality, .restore)
        XCTAssertLessThan(director.surface.confidence, 0.85)
        print("[Scenario] Low energy, no health → personality=\(director.surface.flowPersonality), confidence=\(director.surface.confidence)")
    }

    @MainActor
    func testScenarioRepeatedDeferralCoachMoment() async {
        let task = LifeTask(id: "taxes", title: "File taxes", estimatedMinutes: 45)
        let behavior = BehaviorMemorySnapshot(
            deferralRecords: [TaskDeferralRecord(taskID: "taxes", deferralCount: 4)]
        )
        let store = MockBehaviorStore()
        let env = MockEnvironmentSource(result: EnvironmentContextResult(
            context: EnvironmentContext(energyScore: 0.6, timeOfDay: .morning),
            availability: EnvironmentSignalAvailability(health: true, calendar: true, time: true)
        ))
        let director = FlowDirector(
            behaviorStore: store,
            analysisEngine: MockAnalysisEngine(snapshot: behavior),
            environmentSource: env
        )
        director.session = FlowDirectorSession(
            cognitiveSnapshot: CognitiveSnapshot(energyScore: 0.6),
            pendingTasks: [task],
            currentTime: fixedDate(hour: 11),
            userName: "Sam"
        )
        await director.orchestrate()

        XCTAssertEqual(director.surface.prediction?.actionType, .tryMicro)
        XCTAssertNotNil(director.surface.coachMoment)
        print("[Scenario] 4 deferrals → tryMicro + coach moment")
    }

    @MainActor
    func testScenarioPerformanceUnder50ms() async {
        var tasks: [LifeTask] = []
        for i in 0..<50 {
            tasks.append(LifeTask(title: "Task \(i)", estimatedMinutes: 15 + (i % 20)))
        }
        let env = EnvironmentContext(energyScore: 0.65, freeBlockMinutes: 90, timeOfDay: .morning)
        let (director, _, _) = makeDirector(
            environment: env,
            availability: EnvironmentSignalAvailability(health: true, calendar: true, time: true)
        )
        director.session = FlowDirectorSession(
            cognitiveSnapshot: CognitiveSnapshot(energyScore: 0.65),
            pendingTasks: tasks,
            currentTime: fixedDate(hour: 9),
            userName: "Sam"
        )

        let start = Date()
        await director.orchestrate()
        let ms = Date().timeIntervalSince(start) * 1000
        XCTAssertLessThan(ms, 50)
        print("[Scenario] 50 tasks orchestration → \(String(format: "%.1f", ms))ms")
    }
}

// MARK: - Mocks

private actor MockBehaviorStore: BehaviorMemoryStoreProtocol {
    func recordCompletion(task: LifeTask, durationMinutes: Int, context: EnvironmentContext) async {}
    func recordDeferral(task: LifeTask, context: EnvironmentContext?) async {}
    func recordFlowSession(task: LifeTask?, durationMinutes: Int, context: EnvironmentContext) async {}
    func fetchEvents() async -> [BehaviorEvent] { [] }
    func eventCount() async -> Int { 0 }
    func performRetentionCleanup(
        policy: BehaviorMemoryRetentionPolicy,
        strategy: BehaviorMemoryArchivalStrategy,
        archivalHandler: BehaviorMemoryArchivalHandlerProtocol
    ) async -> BehaviorMemoryCleanupReport { .noOp }
}

private struct MockAnalysisEngine: BehaviorAnalysisEngineProtocol {
    let snapshot: BehaviorMemorySnapshot
    func buildSnapshot(from events: [BehaviorEvent]) async -> BehaviorMemorySnapshot { snapshot }
}

private struct MockEnvironmentSource: EnvironmentContextProviding {
    let result: EnvironmentContextResult
    func currentContext(
        cognitiveSnapshot: CognitiveSnapshot,
        healthSummary: HealthSummary?,
        at date: Date
    ) async -> EnvironmentContextResult { result }
}
