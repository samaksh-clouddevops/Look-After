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

    func testUnscheduledFlexibleTaskExcludedFromTimeline() {
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

        XCTAssertTrue(events.filter { $0.title == "Plan my day" }.isEmpty)
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

    func testRecurrenceOccurrenceUsesScheduledDayNotTemplateDay() {
        let today = makeDate(year: 2026, month: 8, day: 5, hour: 20, minute: 45)
        let day = calendar.startOfDay(for: today)
        var template = LifeTask(
            title: "Morning meds",
            scheduledTime: makeDate(year: 2026, month: 1, day: 1, hour: 8, minute: 30),
            recurrence: .daily,
            schedulingMode: .fixedTime,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        template.createdAt = makeDate(year: 2026, month: 1, day: 1)
        let occurrence = TaskRecurrenceEngine.makeOccurrence(
            from: template,
            template: template,
            scheduledDate: day,
            calendar: calendar
        )

        let events = LifeTimelinePresenter.build(
            tasks: [occurrence],
            completedToday: [],
            recurrenceTemplates: [template],
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: today,
            calendar: calendar
        )

        let event = events.first(where: { $0.title == "Morning meds" })
        XCTAssertNotNil(event)
        XCTAssertEqual(calendar.component(.hour, from: event!.date), 8)
        XCTAssertEqual(calendar.component(.minute, from: event!.date), 30)
        XCTAssertFalse(event!.subtitle.contains("12:00 AM"))
    }

    func testDateOnlyTaskIsNotPastAt845PM() {
        let now = makeDate(year: 2026, month: 8, day: 5, hour: 20, minute: 45)
        let day = calendar.startOfDay(for: now)
        let task = LifeTask(
            title: "Review notes",
            lifeArea: .personal,
            estimatedMinutes: 30,
            scheduledDate: day,
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
        XCTAssertEqual(event?.subtitle, "Flexible today")
        XCTAssertGreaterThan(event!.resolvedEndDate(calendar: calendar), now)
    }

    func testScheduledDateAndTimeCombineOnTimelineDay() {
        let now = makeDate(year: 2026, month: 8, day: 5, hour: 20, minute: 45)
        let day = calendar.startOfDay(for: now)
        let task = LifeTask(
            title: "Evening walk",
            lifeArea: .health,
            estimatedMinutes: 30,
            scheduledDate: day,
            scheduledTime: makeDate(year: 2026, month: 1, day: 1, hour: 21, minute: 0),
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

        let event = events.first(where: { $0.title == "Evening walk" })
        XCTAssertNotNil(event)
        XCTAssertEqual(calendar.component(.hour, from: event!.date), 21)
        XCTAssertEqual(event?.subtitle, "9:00 PM – 9:30 PM")
        XCTAssertFalse(event!.resolvedEndDate(calendar: calendar) < now)
    }

    func testMidnightScheduledTimeTreatedAsFlexibleToday() {
        let now = makeDate(year: 2026, month: 8, day: 5, hour: 20, minute: 45)
        let day = calendar.startOfDay(for: now)
        let task = LifeTask(
            title: "Review notes",
            lifeArea: .personal,
            estimatedMinutes: 30,
            scheduledDate: day,
            scheduledTime: day,
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
        XCTAssertEqual(event?.subtitle, "Flexible today")
        XCTAssertTrue(event!.isFlexibleToday)
    }

    func testTimedTasksSortBeforeFlexibleTasks() {
        let now = makeDate(year: 2026, month: 8, day: 5, hour: 20, minute: 45)
        let day = calendar.startOfDay(for: now)
        let flexible = LifeTask(
            title: "Flexible task",
            scheduledDate: day,
            schedulingMode: .flexible,
            userId: "user-1"
        )
        let timed = LifeTask(
            title: "Morning standup",
            scheduledDate: day,
            scheduledTime: makeDate(year: 2026, month: 1, day: 1, hour: 9, minute: 0),
            schedulingMode: .fixedTime,
            userId: "user-1"
        )

        let events = LifeTimelinePresenter.build(
            tasks: [flexible, timed],
            completedToday: [],
            recurrenceTemplates: [],
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: now,
            calendar: calendar
        )

        let taskEvents = events.filter { !$0.id.hasPrefix("sleep-boundary") }
        XCTAssertEqual(taskEvents.first?.title, "Morning standup")
        XCTAssertEqual(taskEvents.last?.title, "Flexible task")
    }

    func testDuplicateRoutineOccurrenceDedupedOnTimeline() {
        let now = makeDate(year: 2026, month: 8, day: 5, hour: 20, minute: 45)
        let day = calendar.startOfDay(for: now)
        let templateId = "brush-template"
        var template = LifeTask(
            id: templateId,
            title: "Brush teeth — evening",
            recurrence: .daily,
            schedulingMode: .fixedTime,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        template.createdAt = makeDate(year: 2026, month: 1, day: 1)
        let parked = LifeTask(
            id: "parked-brush",
            title: "Brush teeth — evening",
            tags: ["daily-routine"],
            schedulingMode: .flexible,
            userId: "user-1"
        )
        var occurrence = LifeTask(
            id: "today-brush",
            title: "Brush teeth — evening",
            scheduledDate: day,
            scheduledTime: makeDate(year: 2026, month: 1, day: 1, hour: 21, minute: 30),
            schedulingMode: .fixedTime,
            userId: "user-1"
        )
        occurrence.parentTaskId = templateId
        occurrence.tags = ["daily-routine"]

        let events = LifeTimelinePresenter.build(
            tasks: [parked, occurrence],
            completedToday: [],
            recurrenceTemplates: [template],
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: now,
            calendar: calendar
        )

        let brushEvents = events.filter { $0.title.contains("Brush teeth") }
        XCTAssertEqual(brushEvents.count, 1)
        XCTAssertEqual(brushEvents.first?.id, "task-today-brush")
    }

    func testSleepBoundaryIsLastTimelineEvent() {
        let now = makeDate(year: 2026, month: 8, day: 5, hour: 20, minute: 45)
        let day = calendar.startOfDay(for: now)
        let dinner = LifeTask(
            title: "Dinner",
            scheduledDate: day,
            scheduledTime: makeDate(year: 2026, month: 1, day: 1, hour: 19, minute: 0),
            schedulingMode: .fixedTime,
            userId: "user-1"
        )

        let events = LifeTimelinePresenter.build(
            tasks: [dinner],
            completedToday: [],
            recurrenceTemplates: [],
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(events.last?.id.hasPrefix("sleep-boundary") == true)
    }

    func testMorningTimelineProjectsMissingRoutineOccurrences() {
        let now = makeDate(year: 2026, month: 8, day: 6, hour: 7, minute: 0)
        let day = calendar.startOfDay(for: now)
        var template = LifeTask(
            id: "breakfast-template",
            title: "Breakfast",
            scheduledTime: makeDate(year: 2026, month: 1, day: 1, hour: 8, minute: 0),
            tags: ["daily-routine"],
            recurrence: .daily,
            schedulingMode: .fixedTime,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        template.createdAt = makeDate(year: 2026, month: 1, day: 1)
        var superseded = TaskRecurrenceEngine.makeOccurrence(
            from: template,
            template: template,
            scheduledDate: day,
            calendar: calendar
        )
        superseded.status = TaskStatus.superseded

        let events = LifeTimelinePresenter.build(
            tasks: [superseded],
            completedToday: [],
            recurrenceTemplates: [template],
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(events.filter { $0.title == "Breakfast" }.count, 1)
        XCTAssertTrue(events.filter { $0.id.hasPrefix("sleep-boundary") }.isEmpty)
    }

    func testMorningTimelineHasNoSleepBoundary() {
        let now = makeDate(year: 2026, month: 8, day: 6, hour: 7, minute: 0)
        let day = calendar.startOfDay(for: now)
        let breakfast = LifeTask(
            title: "Breakfast",
            scheduledDate: day,
            scheduledTime: makeDate(year: 2026, month: 1, day: 1, hour: 8, minute: 0),
            schedulingMode: .fixedTime,
            userId: "user-1"
        )

        let events = LifeTimelinePresenter.build(
            tasks: [breakfast],
            completedToday: [],
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(events.filter { $0.title == "Breakfast" }.count, 1)
        XCTAssertTrue(events.filter { $0.id.hasPrefix("sleep-boundary") }.isEmpty)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
