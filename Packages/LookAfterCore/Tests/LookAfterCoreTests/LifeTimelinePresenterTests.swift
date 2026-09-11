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

    func testDateOnlyFlexibleIncludedOnTimeline() {
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
        XCTAssertEqual(event?.scheduleKind, .flexibleDay)
    }

    func testDateOnlyAnchoredProjectionUsesRoutineAnchorNotMidnight() {
        let now = makeDate(year: 2026, month: 8, day: 7, hour: 20, minute: 0)
        let day = calendar.startOfDay(for: now)
        var template = LifeTask(
            title: "Dinner",
            estimatedMinutes: 45,
            tags: ["daily-routine"],
            recurrence: .daily,
            schedulingMode: .fixedTime,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        template.createdAt = makeDate(year: 2026, month: 1, day: 1)
        template = TaskConstraintAlignment.align(template)

        let projection = TaskRecurrenceEngine.timelineProjectionOccurrence(
            from: template,
            on: day,
            calendar: calendar
        )

        XCTAssertNotNil(projection.scheduledTime)
        let events = LifeTimelinePresenter.build(
            tasks: [projection],
            completedToday: [],
            recurrenceTemplates: [template],
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: now,
            calendar: calendar
        )

        let event = events.first(where: { $0.title == "Dinner" })
        XCTAssertNotNil(event)
        XCTAssertEqual(calendar.component(.hour, from: event!.date), 19)
        XCTAssertFalse(event!.subtitle.contains("12:00 AM"))
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

    func testMidnightScheduledTimeIncludedAsUnslottedFlexible() {
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
    }

    func testUserPlacedMidnightShowsFlexibleOnTimeline() {
        let now = makeDate(year: 2026, month: 8, day: 5, hour: 20, minute: 45)
        let day = calendar.startOfDay(for: now)
        var task = LifeTask(
            title: "Gym",
            estimatedMinutes: 90,
            scheduledDate: day,
            scheduledTime: day,
            tags: [LifeModel.commitmentTaskTag, "fixed"],
            schedulingMode: .fixedTime,
            userId: "user-1"
        )
        TaskConstraintAlignment.markUserPlaced(&task)
        task = TaskConstraintAlignment.align(task)

        let events = LifeTimelinePresenter.build(
            tasks: [task],
            completedToday: [],
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: now,
            calendar: calendar
        )

        let event = events.first(where: { $0.title == "Gym" })
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.subtitle, "Flexible today")
        XCTAssertFalse(event!.subtitle.contains("12:00 AM"))
    }

    func testAnchoredMidnightPlaceholderShowsFlexibleNotPassed() {
        let now = makeDate(year: 2026, month: 8, day: 5, hour: 20, minute: 45)
        let day = calendar.startOfDay(for: now)
        var task = LifeTask(
            title: "Brush teeth — evening",
            lifeArea: .health,
            estimatedMinutes: 5,
            scheduledDate: day,
            scheduledTime: day,
            tags: ["daily-routine", "fixed"],
            schedulingMode: .fixedTime,
            userId: "user-1"
        )
        task = TaskConstraintAlignment.align(task)

        let events = LifeTimelinePresenter.build(
            tasks: [task],
            completedToday: [],
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: now,
            calendar: calendar
        )

        let event = events.first(where: { $0.title.contains("Brush teeth") })
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.subtitle, "Flexible today")
        XCTAssertFalse(event!.subtitle.contains("12:00 AM"))
        XCTAssertTrue(event!.scheduleKind.isFlexibleToday)
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
        XCTAssertEqual(taskEvents.count, 2)
        XCTAssertEqual(taskEvents.first?.title, "Morning standup")
        XCTAssertEqual(taskEvents.last?.title, "Flexible task")
    }

    func testThreeAnchoredTasksStayInChronologicalOrderWithTimes() {
        let now = makeDate(year: 2026, month: 8, day: 6, hour: 9, minute: 30)
        let day = calendar.startOfDay(for: now)

        let task1 = LifeTask(
            id: "t1",
            title: "Task 1",
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: makeDate(year: 2026, month: 8, day: 6, hour: 10, minute: 0),
            timeConstraint: .anchored,
            scheduledEndTime: makeDate(year: 2026, month: 8, day: 6, hour: 10, minute: 45),
            userId: "user-1"
        )
        let task2 = LifeTask(
            id: "t2",
            title: "Task 2",
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: makeDate(year: 2026, month: 8, day: 6, hour: 11, minute: 0),
            timeConstraint: .anchored,
            scheduledEndTime: makeDate(year: 2026, month: 8, day: 6, hour: 11, minute: 45),
            userId: "user-1"
        )
        let task3 = LifeTask(
            id: "t3",
            title: "Task 3",
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: makeDate(year: 2026, month: 8, day: 6, hour: 13, minute: 0),
            timeConstraint: .anchored,
            scheduledEndTime: makeDate(year: 2026, month: 8, day: 6, hour: 13, minute: 45),
            userId: "user-1"
        )

        let events = LifeTimelinePresenter.build(
            tasks: [task1, task2, task3],
            completedToday: [],
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: now,
            calendar: calendar
        )

        let taskEvents = events.filter { $0.id.hasPrefix("task-") }
        XCTAssertEqual(taskEvents.map(\.title), ["Task 1", "Task 2", "Task 3"])
        XCTAssertFalse(taskEvents.contains(where: \.isFlexibleToday))
        XCTAssertEqual(calendar.component(.hour, from: taskEvents[1].date), 11)
        XCTAssertTrue(taskEvents[1].subtitle.contains("11:00"))
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

    func testDuplicateDinnerTemplatesCollapseToOneEvent() {
        let now = makeDate(year: 2026, month: 8, day: 5, hour: 17, minute: 27)
        let day = calendar.startOfDay(for: now)
        let (templates, occurrences) = duplicateTemplatePair(
            title: "Dinner",
            day: day,
            hour: 19,
            minute: 0,
            durationMinutes: 45
        )

        let events = LifeTimelinePresenter.build(
            tasks: occurrences,
            completedToday: [],
            recurrenceTemplates: templates,
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: now,
            calendar: calendar
        )

        let dinnerEvents = events.filter { $0.title == "Dinner" }
        XCTAssertEqual(dinnerEvents.count, 1)
    }

    func testDuplicateBreakfastTemplatesCollapseToOneEvent() {
        let now = makeDate(year: 2026, month: 8, day: 5, hour: 7, minute: 0)
        let day = calendar.startOfDay(for: now)
        let (templates, occurrences) = duplicateTemplatePair(
            title: "Breakfast",
            day: day,
            hour: 8,
            minute: 0,
            durationMinutes: 20
        )

        let events = LifeTimelinePresenter.build(
            tasks: occurrences,
            completedToday: [],
            recurrenceTemplates: templates,
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: now,
            calendar: calendar
        )

        let breakfastEvents = events.filter { $0.title == "Breakfast" }
        XCTAssertEqual(breakfastEvents.count, 1)
    }

    func testDuplicateGymTemplatesCollapseToOneEvent() {
        let now = makeDate(year: 2026, month: 8, day: 5, hour: 16, minute: 0)
        let day = calendar.startOfDay(for: now)
        let (templates, occurrences) = duplicateTemplatePair(
            title: "Gym",
            day: day,
            hour: 17,
            minute: 27,
            durationMinutes: 90,
            lifeArea: .health
        )

        let events = LifeTimelinePresenter.build(
            tasks: occurrences,
            completedToday: [],
            recurrenceTemplates: templates,
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: now,
            calendar: calendar
        )

        let gymEvents = events.filter { $0.title == "Gym" }
        XCTAssertEqual(gymEvents.count, 1)
    }

    func testLifeCommitmentGymAndRecurringOccurrenceCollapseToOneEvent() {
        let now = makeDate(year: 2026, month: 8, day: 5, hour: 17, minute: 0)
        let day = calendar.startOfDay(for: now)
        let gymStart = makeDate(year: 2026, month: 1, day: 1, hour: 18, minute: 30)
        let gymEnd = makeDate(year: 2026, month: 1, day: 1, hour: 20, minute: 0)

        var commitment = LifeTask(
            id: "gym-commitment",
            title: "Gym",
            lifeArea: .health,
            estimatedMinutes: 90,
            scheduledDate: day,
            scheduledTime: gymStart,
            tags: [LifeModel.commitmentTaskTag, "life-commitment:gym"],
            schedulingMode: .fixedTime,
            scheduledEndTime: gymEnd,
            userId: "user-1"
        )
        commitment.applyTimeConstraint(.anchored)

        var template = LifeTask(
            id: "gym-template",
            title: "Gym",
            lifeArea: .health,
            estimatedMinutes: 90,
            scheduledTime: makeDate(year: 2026, month: 1, day: 1, hour: 17, minute: 27),
            recurrence: .daily,
            schedulingMode: .flexible,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        template.createdAt = makeDate(year: 2026, month: 1, day: 1)
        var occurrence = TaskRecurrenceEngine.makeOccurrence(
            from: template,
            template: template,
            scheduledDate: day,
            calendar: calendar
        )
        occurrence.id = "gym-occurrence"
        occurrence.schedulingMode = .flexible

        let events = LifeTimelinePresenter.build(
            tasks: [commitment, occurrence],
            completedToday: [],
            recurrenceTemplates: [template],
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(events.filter { $0.title == "Gym" }.count, 1)
    }

    func testDuplicateBrushTeethTemplatesCollapseToOneEvent() {
        let now = makeDate(year: 2026, month: 8, day: 5, hour: 21, minute: 0)
        let day = calendar.startOfDay(for: now)
        let (templates, occurrences) = duplicateTemplatePair(
            title: "Brush teeth — evening",
            day: day,
            hour: 21,
            minute: 30,
            durationMinutes: 5,
            lifeArea: .personal
        )

        let events = LifeTimelinePresenter.build(
            tasks: occurrences,
            completedToday: [],
            recurrenceTemplates: templates,
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: now,
            calendar: calendar
        )

        let brushEvents = events.filter { $0.title.contains("Brush teeth") }
        XCTAssertEqual(brushEvents.count, 1)
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
        XCTAssertEqual(events.filter { $0.id.hasPrefix("sleep-boundary") }.count, 0)
    }

    func testMorningTimelineHidesSleepBoundary() {
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
        XCTAssertEqual(events.filter { $0.id.hasPrefix("sleep-boundary") }.count, 0)
        XCTAssertFalse(events.last?.id.hasPrefix("sleep-boundary") == true)
    }

    func testTimelineSignatureStableAcrossShuffledTaskInput() {
        let now = makeDate(year: 2026, month: 8, day: 6, hour: 10, minute: 0)
        let day = calendar.startOfDay(for: now)
        let gym = LifeTask(
            id: "gym",
            title: "Gym",
            estimatedMinutes: 60,
            scheduledDate: day,
            scheduledTime: makeDate(year: 2026, month: 8, day: 6, hour: 18, minute: 30),
            schedulingMode: .fixedTime,
            userId: "user-1"
        )
        let email = LifeTask(
            id: "email",
            title: "Email",
            estimatedMinutes: 30,
            scheduledDate: day,
            scheduledTime: makeDate(year: 2026, month: 8, day: 6, hour: 11, minute: 0),
            schedulingMode: .flexible,
            userId: "user-1"
        )
        let review = LifeTask(
            id: "review",
            title: "Review notes",
            estimatedMinutes: 30,
            scheduledDate: day,
            scheduledTime: makeDate(year: 2026, month: 8, day: 6, hour: 15, minute: 0),
            schedulingMode: .flexible,
            userId: "user-1"
        )

        func signature(from tasks: [LifeTask]) -> String {
            LifeTimelinePresenter.build(
                tasks: tasks,
                completedToday: [],
                bills: [],
                shoppingItems: [],
                contacts: [],
                now: now,
                calendar: calendar
            )
            .map { "\($0.id)|\(Int($0.date.timeIntervalSince1970))" }
            .joined(separator: ";")
        }

        let forward = signature(from: [gym, email, review])
        let reverse = signature(from: [review, email, gym])
        XCTAssertEqual(forward, reverse)
    }

    func testSlottedFlexibleTasksSortByPriorityThenTitle() {
        let now = makeDate(year: 2026, month: 8, day: 6, hour: 10, minute: 0)
        let day = calendar.startOfDay(for: now)
        var high = LifeTask(
            id: "high",
            title: "Zulu task",
            priority: .high,
            scheduledDate: day,
            scheduledTime: makeDate(year: 2026, month: 8, day: 6, hour: 15, minute: 0),
            schedulingMode: .flexible,
            userId: "user-1"
        )
        high.timeConstraint = .flexible
        var low = LifeTask(
            id: "low",
            title: "Alpha task",
            priority: .low,
            scheduledDate: day,
            scheduledTime: makeDate(year: 2026, month: 8, day: 6, hour: 16, minute: 0),
            schedulingMode: .flexible,
            userId: "user-1"
        )
        low.timeConstraint = .flexible

        let events = LifeTimelinePresenter.build(
            tasks: [low, high],
            completedToday: [],
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: now,
            calendar: calendar
        )
        let slotted = events.filter { $0.title == "Zulu task" || $0.title == "Alpha task" }
        XCTAssertEqual(slotted.count, 2)
        XCTAssertEqual(slotted[0].title, "Zulu task")
        XCTAssertEqual(slotted[1].title, "Alpha task")
    }

    private func duplicateTemplatePair(
        title: String,
        day: Date,
        hour: Int,
        minute: Int,
        durationMinutes: Int,
        lifeArea: LifeArea = .health
    ) -> (templates: [LifeTask], occurrences: [LifeTask]) {
        let anchor = makeDate(year: 2026, month: 1, day: 1, hour: hour, minute: minute)
        var template1 = LifeTask(
            id: "\(title)-template-a",
            title: title,
            lifeArea: lifeArea,
            estimatedMinutes: durationMinutes,
            scheduledTime: anchor,
            tags: ["daily-routine"],
            recurrence: .daily,
            schedulingMode: .fixedTime,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        template1.createdAt = makeDate(year: 2026, month: 1, day: 1)
        var template2 = LifeTask(
            id: "\(title)-template-b",
            title: title,
            lifeArea: lifeArea,
            estimatedMinutes: durationMinutes,
            scheduledTime: anchor,
            tags: ["daily-routine"],
            recurrence: .daily,
            schedulingMode: .fixedTime,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        template2.createdAt = makeDate(year: 2026, month: 2, day: 1)

        var occurrence1 = TaskRecurrenceEngine.makeOccurrence(
            from: template1,
            template: template1,
            scheduledDate: day,
            calendar: calendar
        )
        occurrence1.id = "\(title)-occ-a"
        occurrence1.parentTaskId = template1.id

        var occurrence2 = TaskRecurrenceEngine.makeOccurrence(
            from: template2,
            template: template2,
            scheduledDate: day,
            calendar: calendar
        )
        occurrence2.id = "\(title)-occ-b"
        occurrence2.parentTaskId = template2.id

        return ([template1, template2], [occurrence1, occurrence2])
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
