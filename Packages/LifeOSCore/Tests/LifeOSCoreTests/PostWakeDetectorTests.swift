import XCTest
@testable import LifeOSCore

final class PostWakeDetectorTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    func testHealthKitWakeWithinWindowIsPostWake() {
        let now = makeDate(hour: 7, minute: 15)
        let wake = makeDate(hour: 6, minute: 45)

        let result = PostWakeDetector.evaluate(
            PostWakeDetector.Input(now: now, wakeTime: wake, calendar: calendar)
        )

        XCTAssertTrue(result.isPostWake)
        XCTAssertEqual(result.source, .healthKit)
        XCTAssertEqual(result.minutesSinceWake, 30)
    }

    func testHealthKitWakeOutsideWindowIsNotPostWake() {
        let now = makeDate(hour: 10, minute: 0)
        let wake = makeDate(hour: 6, minute: 0)

        let result = PostWakeDetector.evaluate(
            PostWakeDetector.Input(now: now, wakeTime: wake, calendar: calendar)
        )

        XCTAssertFalse(result.isPostWake)
    }

    func testOvernightGapFallbackBeforeNoon() {
        let now = makeDate(hour: 8, minute: 0)
        let lastBackground = calendar.date(byAdding: .hour, value: -8, to: now)!

        let result = PostWakeDetector.evaluate(
            PostWakeDetector.Input(now: now, lastBackgroundAt: lastBackground, calendar: calendar)
        )

        XCTAssertTrue(result.isPostWake)
        XCTAssertEqual(result.source, .overnightGap)
    }

    func testDismissedForTodaySuppressesPostWake() {
        let now = makeDate(hour: 7, minute: 0)
        let wake = makeDate(hour: 6, minute: 30)
        let dismissed = calendar.startOfDay(for: now)

        let result = PostWakeDetector.evaluate(
            PostWakeDetector.Input(
                now: now,
                wakeTime: wake,
                dismissedOnDay: dismissed,
                calendar: calendar
            )
        )

        XCTAssertFalse(result.isPostWake)
    }

    private func makeDate(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 2
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }
}
