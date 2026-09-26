import XCTest
@testable import LookAfterFeatures
import LookAfterCore

final class FreedSlotWindowTests: XCTestCase {
    private let calendar = TestCalendarFixtures.calendar
    private var today: Date { TestCalendarFixtures.today }

    func testFutureTimeOnlyTaskDoesNotFreeToday() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let clock = calendar.date(bySettingHour: 19, minute: 30, second: 0, of: tomorrow)!
        let task = LifeTask(
            title: "Dinner",
            estimatedMinutes: 45,
            scheduledTime: clock,
            userId: "user-1"
        )
        let now = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today)!

        XCTAssertNil(FreedSlotWindow.from(task: task, now: now, calendar: calendar))
    }

    func testUndatedTaskStillFreesASlotFromNow() {
        let task = LifeTask(title: "Inbox", estimatedMinutes: 30, userId: "user-1")
        let now = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today)!

        let window = FreedSlotWindow.from(task: task, now: now, calendar: calendar)
        XCTAssertEqual(window?.start, now)
    }
}
