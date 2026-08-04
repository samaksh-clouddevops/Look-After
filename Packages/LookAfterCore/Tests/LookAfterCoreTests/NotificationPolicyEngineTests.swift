import XCTest
@testable import LookAfterCore

final class NotificationPolicyEngineTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    func testCapsProactiveNotificationsAtTwoPerDay() {
        let now = makeDate(hour: 9, minute: 0)
        let candidates = [
            makeCandidate(kind: .medication, id: "med", fireOffsetMinutes: 10),
            makeCandidate(kind: .meetingPrep, id: "meet", fireOffsetMinutes: 20),
            makeCandidate(kind: .taskDue, id: "task", fireOffsetMinutes: 30),
            makeCandidate(kind: .brainHero, id: "brain", fireOffsetMinutes: 40)
        ]
        let budget = ProactiveDailyBudget(dayKey: ProactiveDailyBudget.dayKey(for: now, calendar: calendar))

        let result = NotificationPolicyEngine.select(
            candidates: candidates,
            preferences: .default,
            budget: budget,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(result.selected.filter(\.kind.countsTowardDailyCap).count, 2)
        XCTAssertEqual(result.selected.map(\.kind), [.medication, .meetingPrep])
        XCTAssertEqual(result.droppedProactiveCount, 2)
    }

    func testRespectsDeliveredBudget() {
        let now = makeDate(hour: 9, minute: 0)
        let dayKey = ProactiveDailyBudget.dayKey(for: now, calendar: calendar)
        var budget = ProactiveDailyBudget(dayKey: dayKey, deliveredCount: 2)
        budget.deliveredCount = 2

        let candidates = [
            makeCandidate(kind: .medication, id: "med", fireOffsetMinutes: 10)
        ]

        let result = NotificationPolicyEngine.select(
            candidates: candidates,
            preferences: .default,
            budget: budget,
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(result.selected.isEmpty)
    }

    func testCategoryOptOutRemovesCandidate() {
        let now = makeDate(hour: 9, minute: 0)
        var preferences = NotificationPreferences.default
        preferences.setEnabled(.medication, false)

        let candidates = [
            makeCandidate(kind: .medication, id: "med", fireOffsetMinutes: 10),
            makeCandidate(kind: .taskDue, id: "task", fireOffsetMinutes: 20)
        ]

        let result = NotificationPolicyEngine.select(
            candidates: candidates,
            preferences: preferences,
            budget: ProactiveDailyBudget(dayKey: ProactiveDailyBudget.dayKey(for: now, calendar: calendar)),
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(result.selected.map(\.kind), [.taskDue])
    }

    func testFocusBreakDoesNotCountTowardCap() {
        let now = makeDate(hour: 9, minute: 0)
        let dayKey = ProactiveDailyBudget.dayKey(for: now, calendar: calendar)
        var budget = ProactiveDailyBudget(dayKey: dayKey, deliveredCount: 2)

        let candidates = [
            makeCandidate(kind: .medication, id: "med", fireOffsetMinutes: 10),
            makeCandidate(kind: .focusBreak, id: "break", fireOffsetMinutes: 15)
        ]

        let result = NotificationPolicyEngine.select(
            candidates: candidates,
            preferences: .default,
            budget: budget,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(result.selected.count, 1)
        XCTAssertEqual(result.selected.first?.kind, .focusBreak)
    }

    func testDismissedCandidateIsExcluded() {
        let now = makeDate(hour: 9, minute: 0)
        let dayKey = ProactiveDailyBudget.dayKey(for: now, calendar: calendar)
        let budget = ProactiveDailyBudget(dayKey: dayKey, dismissedCandidateIDs: ["med"])

        let candidates = [
            makeCandidate(kind: .medication, id: "med", fireOffsetMinutes: 10),
            makeCandidate(kind: .taskDue, id: "task", fireOffsetMinutes: 20)
        ]

        let result = NotificationPolicyEngine.select(
            candidates: candidates,
            preferences: .default,
            budget: budget,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(result.selected.map(\.kind), [.taskDue])
    }

    // MARK: - Helpers

    private func makeCandidate(kind: NotificationKind, id: String, fireOffsetMinutes: Int) -> NotificationCandidate {
        let now = makeDate(hour: 9, minute: 0)
        return NotificationCandidate(
            id: id,
            kind: kind,
            title: kind.displayName,
            body: "Body",
            fireDate: now.addingTimeInterval(TimeInterval(fireOffsetMinutes * 60)),
            route: .briefing
        )
    }

    private func makeDate(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 4
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }
}
