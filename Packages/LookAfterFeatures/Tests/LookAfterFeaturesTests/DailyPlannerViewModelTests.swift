import XCTest
@testable import LookAfterFeatures
import LookAfterCore

@MainActor
final class DailyPlannerViewModelTests: XCTestCase {
    private var calendar: Calendar { TestCalendarFixtures.calendar }
    private var today: Date { TestCalendarFixtures.today }

    func testOverdueOneOffAppearsOnTodayPlanner() {
        let yesterday = TestCalendarFixtures.date(year: 2026, month: 7, day: 30)
        let overdue = LifeTask(
            id: "overdue-one-off",
            title: "Pay invoice",
            status: .pending,
            scheduledDate: yesterday,
            scheduledTime: TestCalendarFixtures.date(year: 2026, month: 7, day: 30, hour: 9),
            userId: "user-1"
        )
        let tomorrow = TestCalendarFixtures.date(year: 2026, month: 8, day: 1)
        let future = LifeTask(
            id: "future-one-off",
            title: "Submit report",
            status: .pending,
            scheduledDate: tomorrow,
            userId: "user-1"
        )
        let todayTask = LifeTask(
            id: "today-task",
            title: "Deep work",
            status: .pending,
            scheduledDate: calendar.startOfDay(for: today),
            userId: "user-1"
        )

        let planned = DailyPlannerViewModel.tasksForPlanningDay(
            from: [overdue, future, todayTask],
            day: calendar.startOfDay(for: today),
            isToday: true,
            calendar: calendar,
            now: today
        )

        XCTAssertEqual(Set(planned.map(\.id)), [overdue.id, todayTask.id])
    }

    func testOverdueOneOffDoesNotAppearOnTomorrowPlanner() {
        let yesterday = TestCalendarFixtures.date(year: 2026, month: 7, day: 30)
        let overdue = LifeTask(
            id: "overdue-one-off",
            title: "Pay invoice",
            status: .pending,
            scheduledDate: yesterday,
            userId: "user-1"
        )
        let tomorrow = TestCalendarFixtures.date(year: 2026, month: 8, day: 1)
        let future = LifeTask(
            id: "future-one-off",
            title: "Submit report",
            status: .pending,
            scheduledDate: tomorrow,
            userId: "user-1"
        )

        let planned = DailyPlannerViewModel.tasksForPlanningDay(
            from: [overdue, future],
            day: tomorrow,
            isToday: false,
            calendar: calendar,
            now: today
        )

        XCTAssertEqual(planned.map(\.id), [future.id])
    }

    func testUnscheduledCreatedTodayAppearsOnTodayPlanner() {
        let createdToday = LifeTask(
            id: "created-today",
            title: "Inbox capture",
            status: .pending,
            createdAt: today,
            userId: "user-1"
        )
        let template = LifeTask(
            id: "template",
            title: "Medication",
            recurrence: .daily,
            userId: "user-1",
            isRecurrenceTemplate: true
        )

        let planned = DailyPlannerViewModel.tasksForPlanningDay(
            from: [createdToday, template],
            day: calendar.startOfDay(for: today),
            isToday: true,
            calendar: calendar,
            now: today
        )

        XCTAssertEqual(planned.map(\.id), [createdToday.id])
    }
}
