import XCTest
@testable import LookAfterCore

final class TimelineNowResolverTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testOverdueIncompleteWorkBeatsWindDownAtMidday() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 9)))
        let now = try XCTUnwrap(calendar.date(bySettingHour: 12, minute: 51, second: 0, of: day))
        let workStart = try XCTUnwrap(calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day))
        let windDown = try XCTUnwrap(calendar.date(bySettingHour: 22, minute: 30, second: 0, of: day))

        let events = [
            LifeTimelineEvent(
                id: "task-work",
                kind: .work,
                title: "Deep work",
                subtitle: "10:00 AM – 10:45 AM",
                date: workStart,
                estimatedMinutes: 45,
                scheduleKind: .fixedWindow
            ),
            LifeTimelineEvent(
                id: "sleep-boundary-1",
                kind: .recovery,
                title: "Wind down · Sleep",
                date: windDown,
                estimatedMinutes: 30,
                isFixed: true
            ),
        ]

        let sorted = TimelineNowResolver.sortedEvents(events, now: now)
        let index = TimelineNowResolver.currentEventIndex(in: sorted, now: now, calendar: calendar)
        let current = try XCTUnwrap(index)
        XCTAssertEqual(sorted[current].title, "Deep work")
        XCTAssertFalse(TimelineDisplaySort.isSleepBoundary(sorted[current]))
    }

    func testInProgressBlockStaysNow() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 9)))
        let now = try XCTUnwrap(calendar.date(bySettingHour: 12, minute: 51, second: 0, of: day))
        let start = try XCTUnwrap(calendar.date(bySettingHour: 11, minute: 45, second: 0, of: day))

        let events = [
            LifeTimelineEvent(
                id: "task-block",
                kind: .work,
                title: "Office work",
                subtitle: "11:45 AM – 1:00 PM",
                date: start,
                estimatedMinutes: 75,
                scheduleKind: .fixedWindow
            ),
            LifeTimelineEvent(
                id: "sleep-boundary-1",
                kind: .recovery,
                title: "Wind down · Sleep",
                date: try XCTUnwrap(calendar.date(bySettingHour: 22, minute: 0, second: 0, of: day)),
                isFixed: true
            ),
        ]

        let sorted = TimelineNowResolver.sortedEvents(events, now: now)
        let index = try XCTUnwrap(TimelineNowResolver.currentEventIndex(in: sorted, now: now, calendar: calendar))
        XCTAssertEqual(sorted[index].title, "Office work")
    }
}

final class SchedulePlacementGuardTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testDinnerAtTenIsRejected() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 9)))
        let ten = try XCTUnwrap(calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day))
        let dinner = LifeTask(
            title: "Dinner",
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: try XCTUnwrap(calendar.date(bySettingHour: 19, minute: 0, second: 0, of: day))
        )

        let result = SchedulePlacementGuard.evaluate(
            proposedStart: ten,
            durationMinutes: 45,
            task: dinner,
            occupied: [],
            calendar: calendar,
            mode: .rejectOutsideBox
        )
        if case .rejected = result {
            // expected
        } else {
            XCTFail("Dinner at 10:00 should be rejected, got \(result)")
        }
    }

    func testDinnerAtNineteenIsAccepted() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 9)))
        let seven = try XCTUnwrap(calendar.date(bySettingHour: 19, minute: 0, second: 0, of: day))
        let dinner = LifeTask(
            title: "Dinner",
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: seven
        )

        let result = SchedulePlacementGuard.evaluate(
            proposedStart: seven,
            durationMinutes: 45,
            task: dinner,
            occupied: [],
            calendar: calendar,
            mode: .rejectOutsideBox
        )
        if case .accepted(let start) = result {
            XCTAssertEqual(calendar.component(.hour, from: start), 19)
        } else {
            XCTFail("Dinner at 19:00 should be accepted, got \(result)")
        }
    }
}
