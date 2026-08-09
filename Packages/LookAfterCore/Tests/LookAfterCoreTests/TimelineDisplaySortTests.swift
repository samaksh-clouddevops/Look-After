import XCTest
@testable import LookAfterCore

final class TimelineDisplaySortTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    /// Midday gap: unslotted flexibles belong before the next timed block and after past timed blocks — not after Dinner.
    func testUnslottedFlexiblesInterleaveBeforeNextTimedBlock() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 7)))
        let now = try XCTUnwrap(calendar.date(bySettingHour: 12, minute: 23, second: 0, of: day))
        let wrapStart = try XCTUnwrap(calendar.date(bySettingHour: 14, minute: 10, second: 0, of: day))
        let dinnerStart = try XCTUnwrap(calendar.date(bySettingHour: 19, minute: 0, second: 0, of: day))

        let events = [
            makeEvent(
                id: "task-standup",
                title: "Daily Stand-up",
                date: try XCTUnwrap(calendar.date(bySettingHour: 10, minute: 30, second: 0, of: day)),
                subtitle: "10:30 AM – 11:00 AM",
                isCompleted: true,
                scheduleKind: .fixedWindow
            ),
            makeEvent(
                id: "task-wrap",
                title: "Office Wrap-up",
                date: wrapStart,
                subtitle: "2:10 PM – 3:10 PM",
                scheduleKind: .flexibleDay
            ),
            makeEvent(
                id: "task-dinner",
                title: "Dinner",
                date: dinnerStart,
                subtitle: "7:00 PM – 7:45 PM",
                isFixed: true,
                scheduleKind: .fixedWindow
            ),
            makeEvent(
                id: "task-vocal",
                title: "Vocal Practice",
                date: day,
                subtitle: "Flexible today",
                scheduleKind: .floating
            ),
            makeEvent(
                id: "task-exercise",
                title: "Exercise",
                date: day,
                subtitle: "Flexible today",
                scheduleKind: .floating
            ),
        ]

        let sorted = TimelineDisplaySort.sorted(events, now: now, calendar: calendar)
        let titles = sorted.map(\.title)

        XCTAssertLessThan(titles.firstIndex(of: "Vocal Practice")!, titles.firstIndex(of: "Office Wrap-up")!)
        XCTAssertLessThan(titles.firstIndex(of: "Office Wrap-up")!, titles.firstIndex(of: "Dinner")!)
        XCTAssertLessThan(titles.firstIndex(of: "Daily Stand-up")!, titles.firstIndex(of: "Vocal Practice")!)
    }

    func testNowMarkerPrefersGapFlexibleOverLaterTimedBlock() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 7)))
        let now = try XCTUnwrap(calendar.date(bySettingHour: 12, minute: 23, second: 0, of: day))

        let events = [
            makeEvent(
                id: "task-wrap",
                title: "Office Wrap-up",
                date: try XCTUnwrap(calendar.date(bySettingHour: 14, minute: 10, second: 0, of: day)),
                subtitle: "2:10 PM – 3:10 PM",
                scheduleKind: .flexibleDay
            ),
            makeEvent(
                id: "task-vocal",
                title: "Vocal Practice",
                date: day,
                subtitle: "Flexible today",
                scheduleKind: .floating
            ),
        ]

        let sorted = TimelineNowResolver.sortedEvents(events, now: now)
        let nowIndex = TimelineNowResolver.currentEventIndex(in: sorted, now: now, calendar: calendar)
        XCTAssertEqual(sorted[nowIndex!].title, "Vocal Practice")
    }

    private func makeEvent(
        id: String,
        title: String,
        date: Date,
        subtitle: String,
        isCompleted: Bool = false,
        isFixed: Bool = false,
        scheduleKind: TimelineScheduleKind
    ) -> LifeTimelineEvent {
        LifeTimelineEvent(
            id: id,
            kind: .work,
            title: title,
            subtitle: subtitle,
            date: date,
            estimatedMinutes: 45,
            isCompleted: isCompleted,
            isFixed: isFixed,
            scheduleKind: scheduleKind
        )
    }
}
