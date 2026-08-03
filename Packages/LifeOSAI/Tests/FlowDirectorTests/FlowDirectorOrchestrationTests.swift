import XCTest
@testable import LifeOSAI
import LifeOSCore

// MARK: - Mocks

private actor MockBehaviorStore: BehaviorMemoryStoreProtocol {
    var events: [BehaviorEvent] = []
    var completionRecorded = false

    func recordCompletion(task: LifeTask, durationMinutes: Int, context: EnvironmentContext) async {
        completionRecorded = true
    }
    func recordDeferral(task: LifeTask, context: EnvironmentContext?) async {}
    func recordFlowSession(task: LifeTask?, durationMinutes: Int, context: EnvironmentContext) async {}
    func fetchEvents() async -> [BehaviorEvent] { events }
    func eventCount() async -> Int { events.count }
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

@MainActor
final class FlowDirectorOrchestrationTests: XCTestCase {

    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    private func makeDirector(
        tasks: [LifeTask],
        environment: EnvironmentContext = EnvironmentContext(energyScore: 0.7, timeOfDay: .morning),
        availability: EnvironmentSignalAvailability = EnvironmentSignalAvailability(
            health: true, calendar: true, device: true, time: true
        ),
        behavior: BehaviorMemorySnapshot = BehaviorMemorySnapshot(recordedEventCount: 10)
    ) -> (FlowDirector, MockBehaviorStore) {
        let store = MockBehaviorStore()
        let session = FlowDirectorSession(
            cognitiveSnapshot: CognitiveSnapshot(energyScore: environment.energyScore),
            pendingTasks: tasks,
            currentTime: FlowDirectorTestFixtures.morningDate,
            userName: "Sam"
        )
        let director = FlowDirector(
            session: session,
            behaviorStore: store,
            analysisEngine: MockAnalysisEngine(snapshot: behavior),
            environmentSource: MockEnvironmentSource(
                result: EnvironmentContextResult(context: environment, availability: availability)
            )
        )
        return (director, store)
    }

    func testOrchestrationPublishesSurface() async {
        let task = LifeTask(title: "API Review", status: .inProgress, estimatedMinutes: 18)
        let (director, _) = makeDirector(tasks: [task])

        await director.orchestrate()

        XCTAssertTrue(director.surface.hasHeroAction)
        XCTAssertEqual(director.surface.heroTask?.title, "API Review")
        XCTAssertFalse(director.isOrchestrating)
        XCTAssertTrue(director.surface.greeting.contains("Sam"))
    }

    func testOrchestrationUsesConfidenceEngine() async {
        let task = LifeTask(title: "Work")
        let (director, _) = makeDirector(
            tasks: [task],
            availability: EnvironmentSignalAvailability(health: false, calendar: false)
        )

        await director.orchestrate()

        XCTAssertLessThan(director.surface.confidence, 0.9)
    }

    func testHandleTaskCompletedRecordsAndReorchestrates() async {
        let task = LifeTask(title: "Done Task", status: .inProgress)
        let (director, store) = makeDirector(tasks: [task])
        await director.orchestrate()

        await director.handleTaskCompleted(task)

        let recorded = await store.completionRecorded
        XCTAssertTrue(recorded)
    }

    func testDirectorDoesNotConstructSurfaceManually() async {
        let task = LifeTask(title: "Focus")
        let (director, _) = makeDirector(tasks: [task])
        await director.orchestrate()

        XCTAssertNotEqual(director.surface, .empty)
        XCTAssertGreaterThan(director.surface.generatedAt, Date.distantPast)
    }

    func testConcurrentOrchestrationCalls() async {
        let task = LifeTask(title: "Stable")
        let (director, _) = makeDirector(tasks: [task])

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask { await director.orchestrate() }
            }
        }

        XCTAssertEqual(director.surface.heroTask?.title, "Stable")
    }
}

// Re-use fixtures from LifeOSCore tests
private enum FlowDirectorTestFixtures {
    static var morningDate: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 31
        components.hour = 9
        return calendar.date(from: components)!
    }
}
