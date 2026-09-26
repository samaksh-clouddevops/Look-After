import XCTest
@testable import LookAfterCore

final class ProactivePhase2Tests: XCTestCase {
    override func tearDown() {
        ProactiveFeedbackStore.resetForFactoryReset()
        ProactiveDismissStore.resetForFactoryReset()
        ProactiveSnapshotStore.resetForFactoryReset()
        ExperimentReminderStore.resetForFactoryReset()
        super.tearDown()
    }

    func testFeedbackBoostAndSuppress() {
        ProactiveFeedbackStore.record(kind: .initiationBridge, outcome: .accepted)
        ProactiveFeedbackStore.record(kind: .initiationBridge, outcome: .accepted)
        XCTAssertGreaterThan(ProactiveFeedbackStore.boost(for: .initiationBridge), 0)

        for _ in 0..<3 {
            ProactiveFeedbackStore.record(kind: .waitingMode, outcome: .dismissed)
        }
        XCTAssertTrue(ProactiveFeedbackStore.shouldSuppress(kind: .waitingMode))
    }

    func testFeedbackWindowFollowsReferenceNow() {
        ProactiveFeedbackStore.resetForFactoryReset()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 10))!
        let recordedAt = calendar.date(byAdding: .day, value: -3, to: now)!

        for _ in 0..<3 {
            ProactiveFeedbackStore.record(kind: .patternCoach, outcome: .dismissed, now: recordedAt)
        }

        XCTAssertTrue(ProactiveFeedbackStore.shouldSuppress(kind: .patternCoach, now: now))
        XCTAssertFalse(
            ProactiveFeedbackStore.shouldSuppress(
                kind: .patternCoach,
                now: calendar.date(byAdding: .day, value: -10, to: recordedAt)!
            )
        )
    }

    func testDismissStoreSnooze() {
        ProactiveDismissStore.snooze(kind: .transitionShield, until: Date().addingTimeInterval(3600))
        let action = ProactiveAction(
            kind: .transitionShield,
            severity: .high,
            message: "Test",
            options: ["OK"]
        )
        XCTAssertTrue(ProactiveDismissStore.isSuppressed(action))
    }

    func testForegroundTrackerDebouncesRapidOpens() {
        AppForegroundTracker.reset()
        let now = Date()
        AppForegroundTracker.recordForeground(at: now)
        AppForegroundTracker.recordForeground(at: now.addingTimeInterval(30))
        AppForegroundTracker.recordForeground(at: now.addingTimeInterval(60))
        XCTAssertEqual(AppForegroundTracker.foregroundCount(within: 20, now: now.addingTimeInterval(60)), 1)
        AppForegroundTracker.recordForeground(at: now.addingTimeInterval(150))
        XCTAssertEqual(AppForegroundTracker.foregroundCount(within: 20, now: now.addingTimeInterval(150)), 2)
    }

    func testTransitionShieldEscalation() {
        let now = Date()
        let start = now.addingTimeInterval(20 * 60)
        let event = LifeTimelineEvent(
            id: "meet-1",
            kind: .meeting,
            title: "Standup",
            date: start,
            isFixed: true
        )
        let transitions = TransitionShieldBuilder.transitions(
            timelineEvents: [event],
            tasks: [],
            now: now
        )
        XCTAssertGreaterThanOrEqual(transitions.count, 2)
        let actions = TransitionShieldBuilder.proactiveActions(from: transitions, now: now)
        XCTAssertTrue(actions.allSatisfy { $0.surface == .notification })
    }

    func testWakeRecoveryCountsReferenceDayNotWallClock() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 7))!
        let events = (9...11).map { hour in
            LifeTimelineEvent(
                id: "meet-\(hour)",
                kind: .meeting,
                title: "Block \(hour)",
                date: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now)!,
                isFixed: true
            )
        }

        let result = WakeRecoveryDetector.evaluate(
            sleepHours: 4.5,
            timelineEvents: events,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(result?.meetingCount, 3)
    }

    func testTransitionShieldIgnoresOtherDayAnchor() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 10))!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let event = LifeTimelineEvent(
            id: "tomorrow-standup",
            kind: .meeting,
            title: "Tomorrow standup",
            date: calendar.date(bySettingHour: 10, minute: 20, second: 0, of: tomorrow)!,
            isFixed: true
        )

        let transitions = TransitionShieldBuilder.transitions(
            timelineEvents: [event],
            tasks: [],
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(transitions.isEmpty)
    }

    func testExperimentFollowThroughMonday() {
        ExperimentReminderStore.save(experiment: "Batch life admin", weekKey: "2026-W30")
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 3
        components.hour = 9
        let calendar = Calendar.current
        let monday = calendar.date(from: components)!
        let action = ExperimentFollowThroughDetector.evaluate(now: monday, calendar: calendar)
        XCTAssertEqual(action?.kind, .experimentReminder)
    }

    func testCaptureClusterAnalyzer() {
        let now = Date()
        let stale = now.addingTimeInterval(-72 * 3600)
        let items = [
            InboxItem(id: "1", content: "apartment lease renewal", status: .unprocessed, createdAt: stale),
            InboxItem(id: "2", content: "apartment lease deposit", status: .needsReview, createdAt: stale)
        ]
        let actions = CaptureClusterAnalyzer.analyze(inboxItems: items, edges: [], now: now)
        XCTAssertFalse(actions.isEmpty)
        XCTAssertEqual(actions.first?.kind, .captureResurrection)
    }

    func testPostCompletionAgentThirdCompletion() {
        let task = LifeTask(id: "t1", title: "Next thing", userId: "u1")
        let actions = PostCompletionAgent.evaluate(completedTodayCount: 3, nextTask: task)
        XCTAssertEqual(actions.first?.kind, .postCompletionMomentum)
    }
}
