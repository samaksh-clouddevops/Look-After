import XCTest
@testable import LookAfterCore

final class PrematurePreferredPlacementTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    }

    func testDinnerParkedOutsideEveningFenceNeedsClear() {
        let day = makeDate(year: 2026, month: 9, day: 10)
        let now = makeDate(year: 2026, month: 9, day: 10, hour: 17, minute: 7)
        var dinner = LifeTask(
            title: "Dinner",
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: makeDate(year: 2026, month: 9, day: 10, hour: 10, minute: 0),
            tags: ["daily-routine"],
            schedulingMode: .flexible
        )
        dinner.temporalBoundingBox = TemporalBoundingBox(earliestStartHour: 17, latestStartHour: 21)

        XCTAssertTrue(
            PrematurePreferredPlacement.needsClear(dinner, on: day, now: now, calendar: calendar)
        )
    }

    func testDinnerParkedAtNowBeforeNineteenNeedsClear() {
        let day = makeDate(year: 2026, month: 9, day: 10)
        let now = makeDate(year: 2026, month: 9, day: 10, hour: 17, minute: 7)
        let dinner = LifeTask(
            title: "Dinner",
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: now,
            tags: ["daily-routine"],
            schedulingMode: .flexible
        )

        XCTAssertTrue(
            PrematurePreferredPlacement.needsClear(
                dinner,
                on: day,
                now: now,
                profile: UserLifeProfile(),
                calendar: calendar
            )
        )
    }

    func testTaskAtPreferredDoesNotClear() {
        let day = makeDate(year: 2026, month: 9, day: 10)
        let now = makeDate(year: 2026, month: 9, day: 10, hour: 12)
        let preferred = makeDate(year: 2026, month: 9, day: 10, hour: 19)
        var dinner = LifeTask(
            title: "Dinner",
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: preferred,
            tags: ["daily-routine"],
            schedulingMode: .flexible
        )
        dinner.temporalBoundingBox = TemporalBoundingBox(earliestStartHour: 17, latestStartHour: 21)

        XCTAssertFalse(
            PrematurePreferredPlacement.needsClear(
                dinner,
                on: day,
                now: now,
                profile: UserLifeProfile(),
                calendar: calendar
            )
        )
    }

    func testClearingPrematureClocksRemovesScheduledTime() {
        let day = makeDate(year: 2026, month: 9, day: 10)
        let now = makeDate(year: 2026, month: 9, day: 10, hour: 17, minute: 7)
        var dinner = LifeTask(
            id: "dinner-1",
            title: "Dinner",
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: makeDate(year: 2026, month: 9, day: 10, hour: 10),
            tags: ["daily-routine"],
            schedulingMode: .flexible
        )
        dinner.temporalBoundingBox = TemporalBoundingBox(earliestStartHour: 17, latestStartHour: 21)

        let cleared = PrematurePreferredPlacement.clearingPrematureClocks(
            in: [dinner],
            on: day,
            now: now,
            calendar: calendar
        )
        XCTAssertNil(cleared[0].scheduledTime)
        XCTAssertNil(cleared[0].scheduledEndTime)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
