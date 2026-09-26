import XCTest
@testable import LookAfterCore

final class TaskNotificationCandidateTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    func testUpcomingTaskFiresOnReferenceDayNotWallClock() {
        let now = date(day: 10, hour: 9)
        let start = date(day: 10, hour: 15)
        let task = LifeTask(
            id: "review",
            title: "Review notes",
            scheduledDate: calendar.startOfDay(for: now),
            scheduledTime: start,
            userId: "user-1"
        )
        let input = NotificationRefreshInput(now: now, tasks: [task])

        let candidates = NotificationCandidateBuilder.build(from: input, calendar: calendar)
        let due = candidates.filter { $0.kind == .taskDue }

        XCTAssertEqual(due.map(\.fireDate), [start])
    }

    func testFutureClockDoesNotNotifyAsOverdueOnReferenceDay() {
        let now = date(day: 10, hour: 9)
        let tomorrowClock = date(day: 11, hour: 19, minute: 30)
        let task = LifeTask(
            id: "dinner",
            title: "Dinner",
            scheduledTime: tomorrowClock,
            userId: "user-1"
        )
        let input = NotificationRefreshInput(now: now, tasks: [task])

        let candidates = NotificationCandidateBuilder.build(from: input, calendar: calendar)
        XCTAssertFalse(candidates.contains { $0.kind == .taskDue })
    }
}
