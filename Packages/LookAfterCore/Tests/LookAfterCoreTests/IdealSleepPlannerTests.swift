import XCTest
@testable import LookAfterCore

final class IdealSleepPlannerTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    func testOfficeAt830WithEightHourTarget() {
        let today = makeDate(year: 2026, month: 8, day: 2, hour: 18, minute: 0)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today))!
        let officeStart = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: tomorrow)!

        var profile = UserLifeProfile()
        profile.workStartHour = 8
        profile.workStartMinute = 30

        let result = IdealSleepPlanner.recommend(
            IdealSleepPlanner.Input(
                now: today,
                targetSleepHours: 8,
                sleepDebtHours: 0,
                profile: profile,
                calendar: calendar
            )
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.line.contains("Ideal tonight:"))
        XCTAssertTrue(result!.line.contains("8:30 AM office"))
        // 8:30 AM - 45m buffer - 8h sleep = 11:45 PM
        let bedtimeHour = calendar.component(.hour, from: result!.bedtime)
        let bedtimeMinute = calendar.component(.minute, from: result!.bedtime)
        XCTAssertEqual(bedtimeHour, 23)
        XCTAssertEqual(bedtimeMinute, 45)
        _ = officeStart // anchor resolved via profile fallback
    }

    func testGymAt630Tomorrow() {
        let today = makeDate(year: 2026, month: 8, day: 2, hour: 19, minute: 0)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today))!
        let gymStart = calendar.date(bySettingHour: 6, minute: 30, second: 0, of: tomorrow)!

        let gymEvent = LifeTimelineEvent(
            id: "gym",
            kind: .exercise,
            title: "Gym",
            date: gymStart,
            isFixed: true
        )

        let result = IdealSleepPlanner.recommend(
            IdealSleepPlanner.Input(
                now: today,
                targetSleepHours: 8,
                tomorrowTimelineEvents: [gymEvent],
                calendar: calendar
            )
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.line.contains("6:30 AM"))
        let bedtimeHour = calendar.component(.hour, from: result!.bedtime)
        XCTAssertLessThan(bedtimeHour, 23)
    }

    func testSleepDebtAddsRecovery() {
        let today = makeDate(year: 2026, month: 8, day: 2, hour: 20, minute: 0)
        var profile = UserLifeProfile()
        profile.workStartHour = 9
        profile.workStartMinute = 0

        let result = IdealSleepPlanner.recommend(
            IdealSleepPlanner.Input(
                now: today,
                targetSleepHours: 8,
                sleepDebtHours: 2,
                profile: profile,
                calendar: calendar
            )
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result!.sleepHours, 9.5)
        XCTAssertTrue(result!.line.contains("catching up on sleep debt"))
    }

    func testHiddenBeforeShowFromHour() {
        let today = makeDate(year: 2026, month: 8, day: 2, hour: 14, minute: 0)
        var profile = UserLifeProfile()
        profile.workStartHour = 9

        let result = IdealSleepPlanner.recommend(
            IdealSleepPlanner.Input(
                now: today,
                targetSleepHours: 8,
                profile: profile,
                calendar: calendar,
                showFromHour: 17
            )
        )

        XCTAssertNil(result)
    }

    func testTomorrowCreativeEventAsAnchor() {
        let today = makeDate(year: 2026, month: 8, day: 2, hour: 18, minute: 0)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today))!
        let creativeStart = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: tomorrow)!

        let event = LifeTimelineEvent(
            id: "music",
            kind: .creative,
            title: "Music production",
            date: creativeStart,
            isFixed: true
        )

        let result = IdealSleepPlanner.recommend(
            IdealSleepPlanner.Input(
                now: today,
                targetSleepHours: 8,
                tomorrowTimelineEvents: [event],
                calendar: calendar
            )
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.line.contains("9:00 PM"))
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)!
    }
}
