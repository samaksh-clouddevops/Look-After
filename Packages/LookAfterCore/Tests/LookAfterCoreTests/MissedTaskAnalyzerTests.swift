import XCTest
@testable import LookAfterCore

final class MissedTaskAnalyzerTests: XCTestCase {
    private let calendar = TestCalendarFixtures.calendar
    private var today: Date { TestCalendarFixtures.today }

    func testMissedFlexibleTaskBeforeNow() {
        let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
        let now = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: today)!
        let task = LifeTask(
            title: "Morning review",
            estimatedMinutes: 30,
            scheduledDate: today,
            scheduledTime: nine,
            schedulingMode: .flexible,
            userId: "user-1"
        )

        let result = MissedTaskAnalyzer.analyze(
            MissedTaskAnalyzer.Input(
                tasks: [task],
                now: now,
                wakeTime: now,
                expectedWakeHour: 7,
                calendar: calendar
            )
        )

        XCTAssertEqual(result.missed.count, 1)
        XCTAssertEqual(result.missed.first?.id, task.id)
        XCTAssertTrue(result.salvageable.isEmpty)
    }

    func testUpcomingTaskIsSalvageable() {
        let twoPM = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: today)!
        let now = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: today)!
        let task = LifeTask(
            title: "Deep work",
            estimatedMinutes: 45,
            scheduledDate: today,
            scheduledTime: twoPM,
            schedulingMode: .flexible,
            userId: "user-1"
        )

        let result = MissedTaskAnalyzer.analyze(
            MissedTaskAnalyzer.Input(tasks: [task], now: now, calendar: calendar)
        )

        XCTAssertTrue(result.missed.isEmpty)
        XCTAssertEqual(result.salvageable.count, 1)
    }

    func testGoingOutWindowOverlapMarksSalvageableNotMissed() {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today)!
        let now = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: today)!
        let task = LifeTask(
            title: "Email batch",
            estimatedMinutes: 45,
            scheduledDate: today,
            scheduledTime: noon,
            schedulingMode: .flexible,
            userId: "user-1"
        )
        let away = MissedTaskAnalyzer.AwayWindow(
            start: calendar.date(bySettingHour: 12, minute: 30, second: 0, of: today)!,
            end: calendar.date(bySettingHour: 14, minute: 30, second: 0, of: today)!
        )

        let result = MissedTaskAnalyzer.analyze(
            MissedTaskAnalyzer.Input(
                tasks: [task],
                now: now,
                awayWindow: away,
                calendar: calendar
            )
        )

        XCTAssertTrue(result.missed.isEmpty)
        XCTAssertEqual(result.salvageable.count, 1)
        XCTAssertEqual(result.salvageable.first?.id, task.id)
    }

    func testMinutesLateWhenWakeAfterExpected() {
        let wake = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: today)!
        let result = MissedTaskAnalyzer.analyze(
            MissedTaskAnalyzer.Input(
                tasks: [],
                now: wake,
                wakeTime: wake,
                expectedWakeHour: 7,
                calendar: calendar
            )
        )
        XCTAssertEqual(result.minutesLate, 150)
    }
}
