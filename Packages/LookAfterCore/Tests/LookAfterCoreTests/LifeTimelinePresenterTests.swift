import XCTest
@testable import LookAfterCore

final class LifeTimelinePresenterTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testWeekdaysFixedTaskExcludedFromSundayTimeline() {
        let sunday = makeDate(year: 2026, month: 8, day: 2, hour: 20)
        let template = LifeTask(
            title: "Work",
            scheduledTime: makeDate(year: 2026, month: 8, day: 1, hour: 8, minute: 30),
            recurrence: .weekdays,
            schedulingMode: .fixedTime,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        let occurrence = TaskRecurrenceEngine.makeOccurrence(
            from: template,
            template: template,
            scheduledDate: sunday,
            calendar: calendar
        )
        let events = LifeTimelinePresenter.build(
            tasks: [occurrence],
            completedToday: [],
            recurrenceTemplates: [template],
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: sunday,
            calendar: calendar
        )

        XCTAssertTrue(events.filter { $0.title == "Work" }.isEmpty)
    }

    func testCustomGymExcludedFromSundayTimeline() {
        let sunday = makeDate(year: 2026, month: 8, day: 2, hour: 20)
        let template = LifeTask(
            title: "Gym",
            scheduledTime: makeDate(year: 2026, month: 8, day: 1, hour: 18, minute: 15),
            recurrence: .custom,
            recurrenceWeekdays: [2, 4, 6],
            schedulingMode: .fixedTime,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        let occurrence = TaskRecurrenceEngine.makeOccurrence(
            from: template,
            template: template,
            scheduledDate: sunday,
            calendar: calendar
        )

        let events = LifeTimelinePresenter.build(
            tasks: [occurrence],
            completedToday: [],
            recurrenceTemplates: [template],
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: sunday,
            calendar: calendar
        )

        XCTAssertTrue(events.filter { $0.title == "Gym" }.isEmpty)
    }

    func testFlexibleTaskStillAppearsWithoutScheduledDay() {
        let sunday = makeDate(year: 2026, month: 8, day: 2, hour: 20)
        let flexible = LifeTask(
            title: "Plan my day",
            lifeArea: .work,
            estimatedMinutes: 15,
            tags: ["onboarding", "flexible"],
            schedulingMode: .flexible,
            userId: "user-1"
        )

        let events = LifeTimelinePresenter.build(
            tasks: [flexible],
            completedToday: [],
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: sunday,
            calendar: calendar
        )

        XCTAssertEqual(events.first?.title, "Plan my day")
    }

    func testCompletedScheduledTaskRemainsOnTimeline() {
        let now = makeDate(year: 2026, month: 8, day: 2, hour: 20)
        var gym = LifeTask(
            title: "Gym",
            scheduledDate: now,
            scheduledTime: makeDate(year: 2026, month: 8, day: 2, hour: 18, minute: 15),
            schedulingMode: .fixedTime,
            userId: "user-1"
        )
        gym.status = .completed
        gym.completedAt = now

        let events = LifeTimelinePresenter.build(
            tasks: [],
            completedToday: [gym],
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(events.filter { $0.title == "Gym" }.count, 1)
        let gymEvent = events.first(where: { $0.title == "Gym" })
        XCTAssertTrue(gymEvent?.isCompleted == true)
        XCTAssertEqual(gymEvent?.estimatedMinutes, gym.estimatedMinutes > 0 ? gym.estimatedMinutes : nil)
        XCTAssertNotNil(gymEvent?.completedAt)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
