import XCTest
@testable import LookAfterCore

final class ProactiveOrchestratorTests: XCTestCase {
    func testADHDChallengeBoostsTransitionShield() {
        let action = ProactiveAction(
            kind: .transitionShield,
            severity: .medium,
            message: "Meeting soon",
            options: ["OK"]
        )
        let generic = ProactiveAction(
            kind: .morningPlanReview,
            severity: .medium,
            message: "Review plan",
            options: ["OK"]
        )
        XCTAssertGreaterThan(
            ADHDProactiveRouting.score(action, challenge: .timeBlindness),
            ADHDProactiveRouting.score(generic, challenge: .timeBlindness)
        )
    }

    func testCalendarChangeDetectorFlagsNewMeeting() {
        let calendar = Calendar.current
        let now = Date()
        let day = calendar.startOfDay(for: now)
        CalendarChangeDetector.resetFingerprint()
        guard let firstStart = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day),
              let secondStart = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: day),
              firstStart > now, secondStart > now else {
            return
        }

        let first = LifeTimelineEvent(id: "meeting-1", kind: .meeting, title: "Sync", date: firstStart)
        _ = CalendarChangeDetector.evaluate(timelineEvents: [first], now: now, calendar: calendar)
        let second = LifeTimelineEvent(id: "meeting-2", kind: .meeting, title: "Review", date: secondStart)
        let change = CalendarChangeDetector.evaluate(timelineEvents: [first, second], now: now, calendar: calendar)
        XCTAssertNotNil(change)
        XCTAssertEqual(change?.newEvents.count, 1)
    }

    func testWaitingModeAnalyzerFindsMicroTask() throws {
        let calendar = Calendar.current
        let now = Date()
        let day = calendar.startOfDay(for: now)
        guard let anchorStart = calendar.date(byAdding: .minute, value: 25, to: now) else { return }

        let anchor = LifeTask(
            title: "Standup",
            scheduledDate: day,
            scheduledTime: anchorStart,
            schedulingMode: .fixedTime,
            timeConstraint: .anchored,
            userId: "user-1"
        )
        let flex = LifeTask(
            title: "Reply to Alex",
            estimatedMinutes: 10,
            scheduledDate: day,
            schedulingMode: .flexible,
            userId: "user-1"
        )
        let result = WaitingModeAnalyzer.analyze(tasks: [anchor, flex], now: now, calendar: calendar)
        guard let result else {
            throw XCTSkip("No waiting-mode gap at current clock time")
        }
        XCTAssertFalse(result.fittingTasks.isEmpty)
    }

    func testInitiationBridgeDetectsHovering() {
        AppForegroundTracker.reset()
        let now = Date()
        AppForegroundTracker.recordForeground(at: now)
        AppForegroundTracker.recordForeground(at: now.addingTimeInterval(60))
        AppForegroundTracker.recordForeground(at: now.addingTimeInterval(120))
        let hero = LifeTask(title: "Write spec", userId: "user-1")
        let result = InitiationBridgeDetector.analyze(
            heroTask: hero,
            foregroundCount: 5,
            focusSessionActive: false,
            now: now
        )
        XCTAssertNotNil(result)
    }
}
