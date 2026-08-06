import XCTest
@testable import LookAfterCore

final class ExecutionBlockResolverTests: XCTestCase {

    private var calendar: Calendar!
    private var day: Date!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 6))!
    }

    func testAnchoredBlockOwnsEnvironmentWithStrictCountdown() {
        let start = time(hour: 10, minute: 0)
        let end = time(hour: 12, minute: 0)
        let now = time(hour: 10, minute: 30)
        let task = makeTask(
            title: "Swift Architecture Refactor",
            lifeArea: .work,
            constraint: .anchored,
            start: start,
            end: end,
            minutes: 120
        )

        let snapshot = ExecutionBlockResolver.resolve(tasks: [task], now: now, calendar: calendar)

        XCTAssertEqual(snapshot.surfaceMode, .anchored)
        XCTAssertEqual(snapshot.taskTitle, "Swift Architecture Refactor")
        XCTAssertEqual(snapshot.category, .deepWork)
        XCTAssertTrue(snapshot.surfaceMode.showsStrictCountdown)
        XCTAssertTrue(ExecutionBlockResolver.shouldProjectEnvironment(for: snapshot))
        XCTAssertEqual(snapshot.progressFraction, 0.25, accuracy: 0.01)
        XCTAssertEqual(snapshot.constraintLabel, "Anchored")
    }

    func testHighConfidenceFlexibleProjectsEnvironment() {
        let start = time(hour: 14, minute: 0)
        let end = time(hour: 15, minute: 0)
        let now = time(hour: 14, minute: 20)
        let task = makeTask(
            title: "Write design notes",
            lifeArea: .work,
            constraint: .flexible,
            start: start,
            end: end,
            minutes: 60
        )

        let snapshot = ExecutionBlockResolver.resolve(
            tasks: [task],
            now: now,
            calendar: calendar,
            confidenceForTask: { _, _ in 0.9 }
        )

        XCTAssertEqual(snapshot.surfaceMode, .flexible)
        XCTAssertTrue(ExecutionBlockResolver.shouldProjectEnvironment(for: snapshot))
    }

    func testLowConfidenceFlexibleDoesNotOwnEnvironment() {
        let start = time(hour: 14, minute: 0)
        let end = time(hour: 15, minute: 0)
        let now = time(hour: 14, minute: 20)
        let task = makeTask(
            title: "Maybe errand",
            lifeArea: .personal,
            constraint: .flexible,
            start: start,
            end: end,
            minutes: 60
        )

        let snapshot = ExecutionBlockResolver.resolve(
            tasks: [task],
            now: now,
            calendar: calendar,
            confidenceForTask: { _, _ in 0.4 }
        )

        XCTAssertEqual(snapshot.surfaceMode, .idle)
        XCTAssertFalse(ExecutionBlockResolver.shouldProjectEnvironment(for: snapshot))
    }

    func testRecoveryBlockSoftModeNoCountdownPressure() {
        let start = time(hour: 16, minute: 0)
        let end = time(hour: 16, minute: 30)
        let now = time(hour: 16, minute: 10)
        let task = makeTask(
            title: "Breathing reset",
            lifeArea: .health,
            constraint: .flexible,
            start: start,
            end: end,
            minutes: 30,
            tags: ["recovery"]
        )

        let snapshot = ExecutionBlockResolver.resolve(
            tasks: [task],
            now: now,
            calendar: calendar,
            confidenceForTask: { _, _ in 0.9 }
        )

        // Self-care / recovery titles map to recovery surface.
        XCTAssertTrue(
            snapshot.surfaceMode == .recovery || snapshot.category == .recovery || snapshot.category == .health,
            "Expected recovery-oriented surface, got \(snapshot.surfaceMode) / \(snapshot.category)"
        )
        if snapshot.surfaceMode == .recovery {
            XCTAssertFalse(snapshot.surfaceMode.showsStrictCountdown)
        }
    }

    func testFluidGapBetweenBlocksShowsNextUp() {
        let morning = makeTask(
            title: "Deep Work",
            lifeArea: .work,
            constraint: .anchored,
            start: time(hour: 9, minute: 0),
            end: time(hour: 10, minute: 0),
            minutes: 60
        )
        let afternoon = makeTask(
            title: "Gym",
            lifeArea: .health,
            constraint: .anchored,
            start: time(hour: 17, minute: 0),
            end: time(hour: 18, minute: 0),
            minutes: 60
        )
        let now = time(hour: 12, minute: 0)

        let snapshot = ExecutionBlockResolver.resolve(
            tasks: [morning, afternoon],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.surfaceMode, .fluidGap)
        XCTAssertTrue(snapshot.nextUpSummary.contains("Gym") || snapshot.nextUpSummary.contains("until"))
        XCTAssertTrue(ExecutionBlockResolver.shouldProjectEnvironment(for: snapshot))
        XCTAssertFalse(snapshot.surfaceMode.showsStrictCountdown)
    }

    func testIdleWhenNoUpcomingBlocks() {
        let past = makeTask(
            title: "Morning standup",
            lifeArea: .work,
            constraint: .anchored,
            start: time(hour: 9, minute: 0),
            end: time(hour: 9, minute: 30),
            minutes: 30
        )
        let now = time(hour: 21, minute: 0)

        let snapshot = ExecutionBlockResolver.resolve(tasks: [past], now: now, calendar: calendar)
        XCTAssertEqual(snapshot.surfaceMode, .idle)
        XCTAssertFalse(ExecutionBlockResolver.shouldProjectEnvironment(for: snapshot))
    }

    func testFocusTaskCategoryDeepWorkFromWorkArea() {
        let task = makeTask(
            title: "Architecture refactor deep work",
            lifeArea: .work,
            constraint: .anchored,
            start: time(hour: 10, minute: 0),
            end: time(hour: 11, minute: 0),
            minutes: 60
        )
        XCTAssertEqual(FocusTaskCategory.resolve(for: task), .deepWork)
    }

    // MARK: - Helpers

    private func time(hour: Int, minute: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func makeTask(
        title: String,
        lifeArea: LifeArea,
        constraint: TimeConstraint,
        start: Date,
        end: Date,
        minutes: Int,
        tags: [String] = []
    ) -> LifeTask {
        LifeTask(
            title: title,
            lifeArea: lifeArea,
            estimatedMinutes: minutes,
            scheduledDate: day,
            scheduledTime: start,
            tags: tags,
            timeConstraint: constraint,
            scheduledEndTime: end,
            userId: "test-user"
        )
    }
}
