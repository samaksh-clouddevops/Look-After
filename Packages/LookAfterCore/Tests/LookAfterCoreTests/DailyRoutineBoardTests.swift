import XCTest
@testable import LookAfterCore

final class DailyRoutineBoardTests: XCTestCase {
    private let calendar = TestCalendarFixtures.calendar
    /// Sunday 2026-09-27 09:00 UTC.
    private var sunday: Date { TestCalendarFixtures.date(year: 2026, month: 9, day: 27, hour: 9) }

    func testSavedWeekdayRoutineStillShowsOnSunday() {
        XCTAssertEqual(calendar.component(.weekday, from: sunday), 1)
        let gym = RoutineBlock(id: "gym", title: "Gym", days: .weekdays, startHour: 7, durationMinutes: 60)
        let rows = DailyRoutineBoard.rows(
            active: [],
            completedToday: [],
            templates: [],
            blocks: [gym],
            now: sunday,
            calendar: calendar
        )
        XCTAssertEqual(rows.map(\.title), ["Gym"])
        XCTAssertTrue(rows[0].tags.contains(DailyRoutineBoard.offTodayTag))
    }

    func testOnboardingFixedTaskCountsWithoutDailyRoutineTag() {
        let breakfast = LifeTask(
            title: "Breakfast",
            scheduledDate: calendar.startOfDay(for: sunday),
            scheduledTime: sunday,
            tags: ["onboarding", "fixed"],
            createdAt: sunday,
            updatedAt: sunday
        )
        let rows = DailyRoutineBoard.rows(
            active: [breakfast],
            completedToday: [],
            templates: [],
            blocks: [],
            now: sunday,
            calendar: calendar
        )
        XCTAssertEqual(rows.map(\.title), ["Breakfast"])
        XCTAssertFalse(rows[0].tags.contains(DailyRoutineBoard.offTodayTag))
    }

    func testTemplateAloneFillsTheRoutineList() {
        var template = LifeTask(
            id: "wind",
            title: "Wind down",
            scheduledTime: TestCalendarFixtures.date(year: 2026, month: 9, day: 27, hour: 22),
            tags: ["daily-routine", "routine"],
            recurrence: .daily,
            createdAt: TestCalendarFixtures.date(year: 2026, month: 9, day: 1),
            updatedAt: sunday
        )
        template.isRecurrenceTemplate = true
        let rows = DailyRoutineBoard.rows(
            active: [],
            completedToday: [],
            templates: [template],
            blocks: [],
            now: sunday,
            calendar: calendar
        )
        XCTAssertEqual(rows.map(\.title), ["Wind down"])
        XCTAssertFalse(rows[0].tags.contains(DailyRoutineBoard.offTodayTag))
    }
}
