import XCTest
@testable import LookAfterCore

final class DayBoundaryPlannerTests: XCTestCase {

    func testActionableDayEndUsesFallbackBeforeEvening() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let end = DayBoundaryPlanner.actionableDayEnd(
            on: day,
            now: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day)!,
            calendar: calendar
        )
        XCTAssertTrue(calendar.isDate(end, inSameDayAs: day))
        XCTAssertGreaterThan(calendar.component(.hour, from: end), 17)
    }

    func testSleepTimelineEventAppearsOnToday() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let evening = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: day)!
        let event = DayBoundaryPlanner.sleepTimelineEvent(on: day, now: evening, calendar: calendar)
        XCTAssertNotNil(event)
        XCTAssertTrue(event!.title.contains("Sleep"))
        XCTAssertEqual(event!.kind, .recovery)
    }

    func testSleepTimelineEventVisibleInMorning() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let morning = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: day)!
        let event = DayBoundaryPlanner.sleepTimelineEvent(on: day, now: morning, calendar: calendar)
        XCTAssertNotNil(event)
        XCTAssertTrue(event!.title.contains("Sleep"))
        XCTAssertTrue(event!.subtitle.contains("Tonight"))
    }
}
