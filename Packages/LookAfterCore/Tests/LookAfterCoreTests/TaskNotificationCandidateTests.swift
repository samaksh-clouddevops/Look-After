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

    func testFutureDatedOneOffWithPastDeadlineDoesNotNotifyAsOverdue() {
        let now = date(day: 10, hour: 9)
        let yesterday = date(day: 9, hour: 18)
        let tomorrow = calendar.startOfDay(for: date(day: 11, hour: 0))
        let task = LifeTask(
            id: "friday-review",
            title: "Friday review",
            deadline: yesterday,
            scheduledDate: tomorrow,
            userId: "user-1"
        )
        let input = NotificationRefreshInput(now: now, tasks: [task])

        let candidates = NotificationCandidateBuilder.build(from: input, calendar: calendar)
        XCTAssertFalse(candidates.contains { $0.kind == .taskDue })
    }

    func testOverdueOneOffCarryForwardNotifiesImmediately() {
        let now = date(day: 10, hour: 9)
        let yesterday = calendar.startOfDay(for: date(day: 9, hour: 0))
        let task = LifeTask(
            id: "pay-rent",
            title: "Pay rent",
            scheduledDate: yesterday,
            userId: "user-1"
        )
        let input = NotificationRefreshInput(now: now, tasks: [task])

        let candidates = NotificationCandidateBuilder.build(from: input, calendar: calendar)
        let due = candidates.filter { $0.kind == .taskDue }
        XCTAssertEqual(due.count, 1)
        XCTAssertEqual(due.first?.fireDate, now.addingTimeInterval(60))
    }

    func testFutureDatedTaskWithTodayDeadlineDoesNotNotify() {
        let now = date(day: 10, hour: 9)
        let tomorrow = calendar.startOfDay(for: date(day: 11, hour: 0))
        let deadlineToday = date(day: 10, hour: 18)
        let task = LifeTask(
            id: "prep-tomorrow",
            title: "Prep tomorrow",
            deadline: deadlineToday,
            scheduledDate: tomorrow,
            userId: "user-1"
        )
        let input = NotificationRefreshInput(now: now, tasks: [task])

        let candidates = NotificationCandidateBuilder.build(from: input, calendar: calendar)
        XCTAssertFalse(candidates.contains { $0.kind == .taskDue })
    }

    func testWrongWeekdayRecurringOccurrenceDoesNotNotify() {
        // Thursday 10 Sep 2026. Sunday is weekday 1.
        let now = date(day: 10, hour: 9)
        let start = date(day: 10, hour: 15)
        let template = LifeTask(
            id: "gym-template",
            title: "Gym",
            recurrence: .custom,
            recurrenceWeekdays: [1],
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        let occurrence = LifeTask(
            id: "gym-thursday",
            title: "Gym",
            scheduledDate: calendar.startOfDay(for: now),
            scheduledTime: start,
            parentTaskId: template.id,
            recurrence: .custom,
            recurrenceWeekdays: [1],
            userId: "user-1"
        )
        let input = NotificationRefreshInput(now: now, tasks: [template, occurrence])

        let candidates = NotificationCandidateBuilder.build(from: input, calendar: calendar)
        XCTAssertFalse(candidates.contains { $0.routePayload == occurrence.id })
    }

}
