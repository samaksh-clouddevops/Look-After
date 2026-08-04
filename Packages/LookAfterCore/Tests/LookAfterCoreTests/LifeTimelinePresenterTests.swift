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

    func testFixedWorkBlockUsesScheduledEndTime() {
        let now = makeDate(year: 2026, month: 8, day: 4, hour: 9)
        let day = calendar.startOfDay(for: now)
        let start = makeDate(year: 2026, month: 8, day: 4, hour: 8, minute: 30)
        let end = makeDate(year: 2026, month: 8, day: 4, hour: 17, minute: 30)
        let office = LifeTask(
            title: "Office",
            lifeArea: .work,
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: start,
            schedulingMode: .fixedTime,
            scheduledEndTime: end,
            userId: "user-1"
        )

        let events = LifeTimelinePresenter.build(
            tasks: [office],
            completedToday: [],
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: now,
            calendar: calendar
        )

        let event = events.first(where: { $0.title == "Office" })
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.subtitle, "8:30 AM – 5:30 PM")
        XCTAssertEqual(event?.estimatedMinutes, 540)
        XCTAssertEqual(event?.scheduleRangeLabel, "8:30 AM – 5:30 PM")
        XCTAssertTrue(event?.isImportantCommitment == true)

        let resolvedEnd = event!.resolvedEndDate(calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: resolvedEnd), 17)
        XCTAssertEqual(calendar.component(.minute, from: resolvedEnd), 30)
    }

    func testFlexibleTaskUsesEstimatedMinutesForWindow() {
        let now = makeDate(year: 2026, month: 8, day: 4, hour: 10)
        let day = calendar.startOfDay(for: now)
        let start = makeDate(year: 2026, month: 8, day: 4, hour: 14)
        let task = LifeTask(
            title: "Review notes",
            lifeArea: .work,
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: start,
            schedulingMode: .flexible,
            userId: "user-1"
        )

        let events = LifeTimelinePresenter.build(
            tasks: [task],
            completedToday: [],
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: now,
            calendar: calendar
        )

        let event = events.first(where: { $0.title == "Review notes" })
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.subtitle, "2:00 PM – 2:45 PM")
        XCTAssertEqual(event?.estimatedMinutes, 45)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
