import XCTest
@testable import LookAfterCore

final class ContextEngineTests: XCTestCase {

    func testMeetingSoonHeroContextLine() {
        let event = CalendarEventReference(
            id: "1",
            title: "Team standup",
            startDate: Date().addingTimeInterval(42 * 60),
            endDate: Date().addingTimeInterval(52 * 60),
            minutesUntilStart: 42
        )
        var environment = EnvironmentContext.baseline
        environment.nextEvent = event
        environment.freeBlockMinutes = 42

        let task = LifeTask(title: "Implement HealthKit import", estimatedMinutes: 30)
        let input = ContextEngineInput(
            cognitiveSnapshot: CognitiveSnapshot(energyScore: 0.75, availableMinutes: 42),
            environment: environment,
            heroTask: task,
            topTasks: [task]
        )

        let briefing = ContextBriefingGenerator().generate(from: ContextEngine().calculate(input), resume: nil)
        XCTAssertTrue(briefing.hero.contextLine?.contains("42 minutes") == true)
        XCTAssertTrue(briefing.hero.actionLine.lowercased().contains("health"))
    }

    func testPoorSleepUsesPlainLanguage() {
        var environment = EnvironmentContext.baseline
        environment.sleepQuality = .poor
        let briefing = ContextBriefingGenerator().generate(
            from: ContextEngine().calculate(ContextEngineInput(environment: environment, now: makeDate(hour: 8))),
            resume: nil,
            now: makeDate(hour: 8),
            peakStartHour: 10
        )
        let joined = ([briefing.hero.actionLine] + briefing.hero.whyNowReasons).joined()
        XCTAssertFalse(joined.lowercased().contains("deep work"))
        XCTAssertFalse(joined.lowercased().contains("flow"))
    }

    func testGroceryDayType() {
        var environment = EnvironmentContext.baseline
        environment.locationContext = .grocery
        let snapshot = ContextEngine().calculate(ContextEngineInput(environment: environment, unpurchasedShoppingCount: 3))
        let briefing = ContextBriefingGenerator().generate(from: snapshot, resume: nil)
        XCTAssertEqual(briefing.hero.dayType, .grocery)
        XCTAssertEqual(briefing.hero.action.kind, .openShopping)
    }

    func testInFlowHero() {
        let task = LifeTask(title: "Search API", estimatedMinutes: 45)
        let session = FlowSessionState(isActive: true, taskID: task.id, elapsedSeconds: 900, targetSeconds: 2700)
        let snapshot = ContextEngine().calculate(ContextEngineInput(
            environment: .baseline,
            activeFlowSession: session,
            heroTask: task,
            topTasks: [task]
        ))
        let briefing = ContextBriefingGenerator().generate(from: snapshot, resume: nil)
        XCTAssertEqual(briefing.hero.dayType, .inFlow)
        XCTAssertTrue(briefing.hero.actionLine.lowercased().contains("search"))
        XCTAssertTrue(briefing.hero.buttonLabel.lowercased().contains("search"))
    }

    func testHeroHasSupportingLine() {
        let task = LifeTask(title: "HealthKit import", estimatedMinutes: 27)
        let snapshot = ContextEngine().calculate(ContextEngineInput(environment: .baseline, heroTask: task, topTasks: [task]))
        let briefing = ContextBriefingGenerator().generate(from: snapshot, resume: nil)
        XCTAssertTrue(briefing.hero.supportingLine.contains("About"))
        XCTAssertTrue(briefing.hero.supportingLine.contains("min"))
        XCTAssertFalse(briefing.hero.actionLine.isEmpty)
        XCTAssertFalse(briefing.hero.buttonLabel.isEmpty)
    }

    private func makeDate(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 31
        components.hour = hour
        components.minute = 30
        return Calendar.current.date(from: components) ?? Date()
    }
}

final class ResumeEngineTests: XCTestCase {
    private var defaults: UserDefaults!
    private var engine: ResumeEngine!

    override func setUp() {
        defaults = UserDefaults(suiteName: "ResumeEngineTests")!
        defaults.removePersistentDomain(forName: "ResumeEngineTests")
        engine = ResumeEngine(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "ResumeEngineTests")
    }

    func testCaptureAndLoadTask() {
        let task = LifeTask(title: "Draft spec", estimatedMinutes: 20)
        engine.captureTask(task, screen: "today", userId: "user-1")
        let loaded = engine.load(userId: "user-1")
        XCTAssertEqual(loaded?.lastTaskTitle, "Draft spec")
    }

    func testStaleSnapshotReturnsNil() {
        let resume = ResumeSnapshot(lastTaskTitle: "Old task", savedAt: Date().addingTimeInterval(-100_000))
        engine.save(resume, userId: "user-2")
        XCTAssertNil(engine.load(userId: "user-2"))
    }
}
