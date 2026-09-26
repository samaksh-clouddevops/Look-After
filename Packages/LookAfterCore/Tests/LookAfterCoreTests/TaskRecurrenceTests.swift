import XCTest
@testable import LookAfterCore

final class TaskRecurrenceTests: XCTestCase {
    private var calendar: Calendar { TestCalendarFixtures.calendar }

    func testDailyRecurrenceFindsTomorrow() {
        let anchor = makeDate(year: 2026, month: 7, day: 31)
        let completed = makeDate(year: 2026, month: 7, day: 31, hour: 8)

        let next = TaskRecurrence.daily.nextOccurrence(after: completed, anchoredOn: anchor, calendar: calendar)

        XCTAssertEqual(next, makeDate(year: 2026, month: 8, day: 1))
    }

    func testWeekdaysRecurrenceSkipsWeekend() {
        let friday = makeDate(year: 2026, month: 7, day: 31)
        let next = TaskRecurrence.weekdays.nextOccurrence(after: friday, anchoredOn: friday, calendar: calendar)

        XCTAssertEqual(next, makeDate(year: 2026, month: 8, day: 3))
    }

    func testWeeklyRecurrenceFindsSameWeekdayNextWeek() {
        let anchor = makeDate(year: 2026, month: 7, day: 24)
        let completed = makeDate(year: 2026, month: 7, day: 31)

        let next = TaskRecurrence.weekly.nextOccurrence(after: completed, anchoredOn: anchor, calendar: calendar)

        XCTAssertEqual(next, makeDate(year: 2026, month: 8, day: 7))
    }

    func testMonthlyRecurrenceFindsSameDayNextMonth() {
        let anchor = makeDate(year: 2026, month: 7, day: 15)
        let completed = makeDate(year: 2026, month: 7, day: 15)

        let next = TaskRecurrence.monthly.nextOccurrence(after: completed, anchoredOn: anchor, calendar: calendar)

        XCTAssertEqual(next, makeDate(year: 2026, month: 8, day: 15))
    }

    func testRecurrenceEngineCreatesOccurrenceWithoutRecurrenceField() {
        let template = LifeTask(
            title: "Take Thyroid Medication",
            scheduledDate: makeDate(year: 2026, month: 7, day: 31),
            recurrence: .daily,
            userId: "user-1",
            isRecurrenceTemplate: true
        )

        let occurrence = TaskRecurrenceEngine.makeOccurrence(
            from: template,
            template: template,
            scheduledDate: makeDate(year: 2026, month: 7, day: 31)
        )

        XCTAssertEqual(occurrence.title, template.title)
        XCTAssertEqual(occurrence.parentTaskId, template.id)
        XCTAssertEqual(occurrence.status, TaskStatus.pending)
        XCTAssertNil(occurrence.completedAt)
        XCTAssertEqual(occurrence.recurrenceRule, .none)
    }

    func testMissingOccurrencesSkipsWhenDayAlreadyHasOccurrence() {
        let template = LifeTask(
            title: "Drink Water",
            recurrence: .daily,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        let today = makeDate(year: 2026, month: 7, day: 31)
        var completed = TaskRecurrenceEngine.makeOccurrence(from: template, template: template, scheduledDate: today)
        completed.status = TaskStatus.completed
        completed.completedAt = today

        let missing = TaskRecurrenceEngine.missingOccurrences(for: [template, completed], on: today, calendar: calendar)
        XCTAssertTrue(missing.isEmpty)
    }

    func testMissingOccurrencesSkipsWhenSupersededRowExists() {
        let template = LifeTask(
            title: "Brush teeth — morning",
            scheduledTime: makeDate(year: 2026, month: 1, day: 1, hour: 7, minute: 30),
            recurrence: .daily,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        let today = makeDate(year: 2026, month: 8, day: 6)
        var superseded = TaskRecurrenceEngine.makeOccurrence(from: template, template: template, scheduledDate: today, calendar: calendar)
        superseded.status = .superseded

        let missing = TaskRecurrenceEngine.missingOccurrences(for: [template, superseded], on: today, calendar: calendar)
        XCTAssertTrue(missing.isEmpty)
    }

    func testMissingOccurrencesSkipsTimeOnlyStoredOccurrence() {
        let template = LifeTask(
            id: "dinner-template",
            title: "Dinner",
            scheduledTime: makeDate(year: 2026, month: 1, day: 1, hour: 19, minute: 30),
            recurrence: .daily,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        let today = makeDate(year: 2026, month: 8, day: 7)
        let timeOnly = LifeTask(
            id: "dinner-time-only",
            title: "Dinner",
            status: .pending,
            scheduledTime: makeDate(year: 2026, month: 8, day: 7, hour: 19, minute: 30),
            parentTaskId: template.id,
            userId: "user-1"
        )

        let missing = TaskRecurrenceEngine.missingOccurrences(
            for: [template, timeOnly],
            on: today,
            calendar: calendar
        )
        XCTAssertTrue(missing.isEmpty)

        let projected = TaskRecurrenceEngine.timelineProjections(
            for: [template, timeOnly],
            on: today,
            calendar: calendar
        )
        XCTAssertTrue(projected.isEmpty)
    }

    func testCompletedTimeOnlyOccurrenceFulfillsSeries() {
        let template = LifeTask(
            id: "dinner-template",
            title: "Dinner",
            scheduledTime: makeDate(year: 2026, month: 1, day: 1, hour: 19, minute: 30),
            recurrence: .daily,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        let today = makeDate(year: 2026, month: 8, day: 7)
        var completed = LifeTask(
            id: "dinner-time-only-done",
            title: "Dinner",
            status: .completed,
            scheduledTime: makeDate(year: 2026, month: 8, day: 7, hour: 19, minute: 30),
            parentTaskId: template.id,
            userId: "user-1"
        )
        completed.completedAt = nil

        XCTAssertTrue(
            TaskRecurrenceEngine.isSeriesFulfilled(
                on: today,
                for: template,
                in: [template, completed],
                calendar: calendar
            )
        )
        XCTAssertTrue(
            TaskRecurrenceEngine.missingOccurrences(
                for: [template, completed],
                on: today,
                calendar: calendar
            ).isEmpty
        )
    }



    func testTimelineProjectionsAfterSupersededOccurrence() {
        let template = LifeTask(
            title: "Brush teeth — morning",
            scheduledTime: makeDate(year: 2026, month: 1, day: 1, hour: 7, minute: 30),
            recurrence: .daily,
            createdAt: makeDate(year: 2026, month: 7, day: 1),
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        let today = makeDate(year: 2026, month: 8, day: 6)
        var superseded = TaskRecurrenceEngine.makeOccurrence(from: template, template: template, scheduledDate: today, calendar: calendar)
        superseded.status = .superseded

        let projected = TaskRecurrenceEngine.timelineProjections(for: [template, superseded], on: today, calendar: calendar)
        XCTAssertEqual(projected.count, 1)
        XCTAssertEqual(projected.first?.title, template.title)
        XCTAssertEqual(projected.first?.parentTaskId, template.id)
        XCTAssertEqual(
            projected.first?.id,
            TaskRecurrenceEngine.stableProjectionID(templateId: template.id, on: today, calendar: calendar)
        )
    }

    func testRecurrenceEngineCreatesNextOccurrenceAfterCompletion() {
        var template = LifeTask(
            title: "Take Thyroid Medication",
            scheduledDate: makeDate(year: 2026, month: 7, day: 31),
            recurrence: .daily,
            userId: "user-1"
        )
        template.createdAt = makeDate(year: 2026, month: 7, day: 31)

        var completed = template
        completed.status = TaskStatus.completed
        completed.completedAt = makeDate(year: 2026, month: 7, day: 31, hour: 8)

        let nextDate = TaskRecurrenceEngine.nextScheduledDate(for: completed, template: template, calendar: calendar)
        XCTAssertEqual(nextDate, makeDate(year: 2026, month: 8, day: 1))

        let nextTask = TaskRecurrenceEngine.makeNextOccurrence(
            from: completed,
            template: template,
            scheduledDate: nextDate!,
            calendar: calendar
        )

        XCTAssertEqual(nextTask.title, template.title)
        XCTAssertEqual(nextTask.parentTaskId, template.id)
        XCTAssertEqual(nextTask.status, TaskStatus.pending)
        XCTAssertNil(nextTask.completedAt)
    }

    func testCompletedTaskShouldNotBeActive() {
        let task = LifeTask(title: "Done task", status: .completed, completedAt: Date())
        XCTAssertTrue(task.isCompleted)
        XCTAssertFalse(task.status.isActive)
    }

    func testCustomWeekdayRecurrenceMatchesSelectedDays() {
        let anchor = makeDate(year: 2026, month: 7, day: 31) // Friday
        let weekdays = [2, 4, 6] // Mon, Wed, Fri

        XCTAssertTrue(TaskRecurrence.custom.occurs(on: makeDate(year: 2026, month: 7, day: 31), anchoredOn: anchor, weekdays: weekdays, calendar: calendar))
        XCTAssertFalse(TaskRecurrence.custom.occurs(on: makeDate(year: 2026, month: 8, day: 1), anchoredOn: anchor, weekdays: weekdays, calendar: calendar)) // Saturday
    }

    func testCustomRecurrenceFindsNextSelectedWeekday() {
        let anchor = makeDate(year: 2026, month: 7, day: 31) // Friday
        let weekdays = [2, 4, 6] // Mon, Wed, Fri
        let completed = makeDate(year: 2026, month: 7, day: 31, hour: 19)

        let next = TaskRecurrence.custom.nextOccurrence(
            after: completed,
            anchoredOn: anchor,
            weekdays: weekdays,
            calendar: calendar
        )

        XCTAssertEqual(next, makeDate(year: 2026, month: 8, day: 3)) // Monday
    }

    func testRecurrenceEngineCopiesFixedTimeFields() {
        let start = makeDate(year: 2026, month: 7, day: 31, hour: 9)
        let end = makeDate(year: 2026, month: 7, day: 31, hour: 17)
        let template = LifeTask(
            title: "Office",
            scheduledDate: makeDate(year: 2026, month: 7, day: 31),
            scheduledTime: start,
            recurrence: .weekdays,
            schedulingMode: .fixedTime,
            scheduledEndTime: end
        )

        var completed = template
        completed.status = .completed
        completed.completedAt = end

        let nextDate = makeDate(year: 2026, month: 8, day: 3)
        let nextTask = TaskRecurrenceEngine.makeNextOccurrence(
            from: completed,
            template: template,
            scheduledDate: nextDate,
            calendar: calendar
        )

        XCTAssertEqual(nextTask.schedulingMode, .fixedTime)
        XCTAssertNotNil(nextTask.scheduledTime)
        XCTAssertNotNil(nextTask.scheduledEndTime)
        let startHour = calendar.component(.hour, from: nextTask.scheduledTime!)
        XCTAssertEqual(startHour, 9)
    }

    func testFixedTimeEventIsDetectedDuringWindow() {
        let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        let end = calendar.date(bySettingHour: 17, minute: 30, second: 0, of: Date())!
        let task = LifeTask(title: "Office", scheduledTime: start, schedulingMode: .fixedTime, scheduledEndTime: end)
        let midday = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        XCTAssertTrue(task.isFixedTimeEvent)
        XCTAssertTrue(task.isActiveFixedTimeWindow(at: midday, calendar: calendar))
    }

    func testFixedTimeEventDoesNotRemapTomorrowClockOntoToday() {
        let today = makeDate(year: 2026, month: 8, day: 2, hour: 10)
        let tomorrowNine = makeDate(year: 2026, month: 8, day: 3, hour: 9)
        let tomorrowEnd = makeDate(year: 2026, month: 8, day: 3, hour: 10)
        let task = LifeTask(
            title: "Dentist",
            scheduledDate: makeDate(year: 2026, month: 8, day: 3),
            scheduledTime: tomorrowNine,
            schedulingMode: .fixedTime,
            scheduledEndTime: tomorrowEnd
        )
        XCTAssertTrue(task.isFixedTimeEvent)
        XCTAssertFalse(task.isActiveFixedTimeWindow(at: today, calendar: calendar))
    }

    func testFixedTimeEventDoesNotRemapYesterdayClockOntoToday() {
        let today = makeDate(year: 2026, month: 8, day: 2, hour: 10)
        let yesterdayNine = makeDate(year: 2026, month: 8, day: 1, hour: 9)
        let yesterdayEnd = makeDate(year: 2026, month: 8, day: 1, hour: 10)
        let task = LifeTask(
            title: "Standup",
            scheduledDate: makeDate(year: 2026, month: 8, day: 1),
            scheduledTime: yesterdayNine,
            schedulingMode: .fixedTime,
            scheduledEndTime: yesterdayEnd
        )
        XCTAssertTrue(task.isFixedTimeEvent)
        XCTAssertFalse(task.isActiveFixedTimeWindow(at: today, calendar: calendar))
    }

    func testWeekdaysOccurrenceNotActionableOnSunday() {
        let sunday = makeDate(year: 2026, month: 8, day: 2)
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
        let allTasks = [template, occurrence]

        XCTAssertFalse(
            TaskRecurrenceEngine.matchesRecurrenceSchedule(occurrence, on: sunday, in: allTasks, calendar: calendar)
        )
        XCTAssertFalse(
            TaskRecurrenceEngine.isActionableToday(occurrence, in: allTasks, calendar: calendar, referenceDate: sunday)
        )
    }

    func testCustomOccurrenceNotActionableOnUnselectedDay() {
        let saturday = makeDate(year: 2026, month: 8, day: 1)
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
            scheduledDate: saturday,
            calendar: calendar
        )
        let allTasks = [template, occurrence]

        XCTAssertFalse(
            TaskRecurrenceEngine.isActionableToday(occurrence, in: allTasks, calendar: calendar, referenceDate: saturday)
        )
    }

    func testInvalidOccurrenceIDsDetectsWrongDayInstances() {
        let sunday = makeDate(year: 2026, month: 8, day: 2)
        let template = LifeTask(
            title: "Work",
            recurrence: .weekdays,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        let occurrence = TaskRecurrenceEngine.makeOccurrence(
            from: template,
            template: template,
            scheduledDate: sunday,
            calendar: calendar
        )
        let ids = TaskRecurrenceEngine.invalidOccurrenceIDs(in: [template, occurrence], calendar: calendar)
        XCTAssertEqual(ids, [occurrence.id])
    }

    func testInvalidOccurrenceIDsDetectsTimeOnlyWrongDay() {
        let sunday = makeDate(year: 2026, month: 8, day: 2, hour: 9)
        let template = LifeTask(
            id: "work-template",
            title: "Work",
            recurrence: .weekdays,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        let occurrence = LifeTask(
            id: "work-sunday-clock",
            title: "Work",
            status: .pending,
            scheduledTime: sunday,
            parentTaskId: template.id,
            recurrence: .weekdays,
            userId: "user-1"
        )
        let ids = TaskRecurrenceEngine.invalidOccurrenceIDs(in: [template, occurrence], calendar: calendar)
        XCTAssertEqual(ids, [occurrence.id])
    }


    func testOccurrenceRecurrenceOverridesTemplateForScheduleCheck() {
        let sunday = makeDate(year: 2026, month: 8, day: 2)
        // Anchor must precede the dates under test — default createdAt is wall-clock.
        let template = LifeTask(
            title: "Gym",
            recurrence: .daily,
            createdAt: makeDate(year: 2026, month: 7, day: 1),
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        var occurrence = TaskRecurrenceEngine.makeOccurrence(
            from: template,
            template: template,
            scheduledDate: sunday,
            calendar: calendar
        )
        occurrence.recurrence = .custom
        occurrence.recurrenceWeekdays = [2, 3, 4, 5, 6, 7] // Mon–Sat
        let allTasks = [template, occurrence]

        XCTAssertFalse(
            TaskRecurrenceEngine.matchesRecurrenceSchedule(occurrence, on: sunday, in: allTasks, calendar: calendar),
            "Sunday must not match Mon–Sat override"
        )
        XCTAssertTrue(
            TaskRecurrenceEngine.matchesRecurrenceSchedule(
                occurrence,
                on: makeDate(year: 2026, month: 8, day: 3),
                in: allTasks,
                calendar: calendar
            ),
            "Monday must match Mon–Sat override"
        )
    }

    func testInvalidScheduledTaskIDsIncludesLegacyWrongDayTask() {
        let sunday = makeDate(year: 2026, month: 8, day: 2)
        let legacy = LifeTask(
            title: "Gym",
            scheduledDate: sunday,
            recurrence: .custom,
            recurrenceWeekdays: [2, 3, 4, 5, 6, 7],
            userId: "user-1"
        )
        let ids = TaskRecurrenceEngine.invalidScheduledTaskIDs(in: [legacy], calendar: calendar)
        XCTAssertEqual(ids, [legacy.id])
    }

    func testOrphanOccurrenceFailsScheduleCheck() {
        let sunday = makeDate(year: 2026, month: 8, day: 2)
        let orphan = LifeTask(
            title: "Gym",
            scheduledDate: sunday,
            scheduledTime: makeDate(year: 2026, month: 8, day: 2, hour: 18, minute: 15),
            parentTaskId: "missing-template",
            userId: "user-1"
        )
        XCTAssertFalse(
            TaskRecurrenceEngine.matchesRecurrenceSchedule(orphan, on: sunday, in: [orphan], calendar: calendar)
        )
        XCTAssertEqual(TaskRecurrenceEngine.invalidScheduledTaskIDs(in: [orphan], calendar: calendar), [orphan.id])
    }

    func testDuplicateLegacyDailyGymRemovedWhenTemplateExists() {
        let sunday = makeDate(year: 2026, month: 8, day: 2)
        let template = LifeTask(
            title: "Gym",
            recurrence: .custom,
            recurrenceWeekdays: [2, 3, 4, 5, 6, 7],
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        let legacyDaily = LifeTask(
            title: "Gym",
            scheduledDate: sunday,
            recurrence: .daily,
            userId: "user-1"
        )
        let allTasks = [template, legacyDaily]

        XCTAssertFalse(
            TaskRecurrenceEngine.matchesRecurrenceSchedule(legacyDaily, on: sunday, in: allTasks, calendar: calendar)
        )
        XCTAssertEqual(
            TaskRecurrenceEngine.invalidScheduledTaskIDs(in: allTasks, calendar: calendar),
            [legacyDaily.id]
        )
    }

    func testTimeOnlyLegacyDuplicateRemovedWhenTemplateExists() {
        let clock = makeDate(year: 2026, month: 8, day: 2, hour: 18)
        let template = LifeTask(
            id: "gym-template",
            title: "Gym",
            recurrence: .daily,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        let legacy = LifeTask(
            id: "gym-legacy-clock",
            title: "Gym",
            status: .pending,
            scheduledTime: clock,
            recurrence: .daily,
            userId: "user-1"
        )
        let allTasks = [template, legacy]

        XCTAssertFalse(
            TaskRecurrenceEngine.matchesRecurrenceSchedule(legacy, on: clock, in: allTasks, calendar: calendar)
        )
        XCTAssertEqual(
            TaskRecurrenceEngine.invalidScheduledTaskIDs(in: allTasks, calendar: calendar),
            [legacy.id]
        )
    }

    func testTimeOnlyKeeperBeatsDatedRowOnAnotherDay() {
        let today = makeDate(year: 2026, month: 8, day: 6, hour: 8)
        let tomorrow = makeDate(year: 2026, month: 8, day: 7, hour: 8)
        let clocked = LifeTask(
            id: "brush-clock",
            title: "Brush teeth",
            status: .pending,
            scheduledTime: today,
            parentTaskId: "tmpl-brush",
            userId: "user-1"
        )
        let datedElsewhere = LifeTask(
            id: "brush-tomorrow",
            title: "Brush teeth",
            status: .pending,
            scheduledDate: tomorrow,
            parentTaskId: "tmpl-brush",
            userId: "user-1"
        )

        let keeper = TaskScheduleQuery.preferredKeeper(
            in: [datedElsewhere, clocked],
            on: today,
            calendar: calendar
        )

        XCTAssertEqual(keeper?.id, clocked.id)
    }



    func testRecurrenceCompactorDropsSupersededAndDuplicateSameDayRows() {
        let day = makeDate(year: 2026, month: 8, day: 6)
        let template = LifeTask(
            id: "tmpl-brush",
            title: "Brush teeth",
            recurrence: .daily,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        let keeper = LifeTask(
            id: "occ-keeper",
            title: "Brush teeth",
            status: .pending,
            scheduledDate: day,
            parentTaskId: template.id,
            userId: "user-1"
        )
        let duplicate = LifeTask(
            id: "occ-dup",
            title: "Brush teeth",
            status: .pending,
            scheduledDate: day,
            parentTaskId: template.id,
            userId: "user-1"
        )
        let superseded = LifeTask(
            id: "occ-old",
            title: "Brush teeth",
            status: .superseded,
            scheduledDate: calendar.date(byAdding: .day, value: -1, to: day),
            parentTaskId: template.id,
            userId: "user-1"
        )
        let input = [template, keeper, duplicate, superseded]
        let (pruned, removed) = TaskRecurrenceCompactor.compact(input, referenceDate: day)
        XCTAssertEqual(removed, 2)
        XCTAssertEqual(pruned.count, 2)
        XCTAssertTrue(pruned.contains(where: { $0.id == template.id }))
        let occurrenceIDs = Set(pruned.map { $0.id })
        XCTAssertTrue(occurrenceIDs.contains(keeper.id) || occurrenceIDs.contains(duplicate.id))
        XCTAssertFalse(occurrenceIDs.contains(superseded.id))
    }

    func testCompactorDropsTimeOnlyDuplicateOnSameClockDay() {
        let day = makeDate(year: 2026, month: 8, day: 6, hour: 8)
        let later = makeDate(year: 2026, month: 8, day: 6, hour: 21)
        let template = LifeTask(
            id: "tmpl-brush",
            title: "Brush teeth",
            recurrence: .daily,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        let keeper = LifeTask(
            id: "occ-clock-keeper",
            title: "Brush teeth",
            status: .pending,
            scheduledTime: day,
            parentTaskId: template.id,
            userId: "user-1"
        )
        let duplicate = LifeTask(
            id: "occ-clock-dup",
            title: "Brush teeth",
            status: .pending,
            scheduledTime: later,
            parentTaskId: template.id,
            userId: "user-1"
        )
        let (pruned, removed) = TaskRecurrenceCompactor.compact(
            [template, keeper, duplicate],
            calendar: calendar,
            referenceDate: day
        )

        XCTAssertEqual(removed, 1)
        XCTAssertEqual(pruned.filter { $0.parentTaskId != nil }.count, 1)
    }

    func testCompletedTemplateClockDoesNotHideTheNextDay() {
        let yesterday = makeDate(year: 2026, month: 8, day: 6, hour: 10)
        let today = makeDate(year: 2026, month: 8, day: 7, hour: 10)
        var template = LifeTask(
            id: "late-dinner",
            title: "Late dinner",
            status: .completed,
            scheduledTime: makeDate(year: 2026, month: 8, day: 7, hour: 20, minute: 30),
            tags: ["daily-routine"],
            recurrence: .daily,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        template.createdAt = makeDate(year: 2026, month: 8, day: 6)
        template.completedAt = yesterday

        let fresh = TaskRecurrenceEngine.missingOccurrences(
            for: [template],
            on: today,
            calendar: calendar
        )
        XCTAssertEqual(fresh.count, 1)
        XCTAssertEqual(fresh.first?.title, "Late dinner")
        XCTAssertFalse(TaskRecurrenceEngine.isSeriesFulfilled(
            on: today,
            for: template,
            in: [template],
            calendar: calendar
        ))

        var occurrence = fresh[0]
        occurrence.status = .completed
        occurrence.completedAt = today
        let events = DayPlateBuilder.events(
            from: [template, occurrence],
            now: today,
            referenceDay: today,
            calendar: calendar
        )
        let dinner = events.filter { $0.title == "Late dinner" }
        XCTAssertEqual(dinner.count, 1)
        XCTAssertEqual(dinner.first?.isCompleted, true)
    }

    func testCompactorDropsSkippedTimeOnlyRowPastRetention() {
        let today = makeDate(year: 2026, month: 8, day: 20, hour: 9)
        let oldClock = makeDate(year: 2026, month: 8, day: 1, hour: 8)
        let template = LifeTask(
            id: "tmpl-meds",
            title: "Meds",
            recurrence: .daily,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        let skipped = LifeTask(
            id: "occ-skipped-clock",
            title: "Meds",
            status: .skipped,
            scheduledTime: oldClock,
            parentTaskId: template.id,
            updatedAt: today,
            userId: "user-1"
        )
        let (pruned, removed) = TaskRecurrenceCompactor.compact(
            [template, skipped],
            retentionDays: 7,
            referenceDate: today
        )

        XCTAssertEqual(removed, 1)
        XCTAssertFalse(pruned.contains { $0.id == skipped.id })
    }

    func testTimeOnlyLegacySharesTitleSeriesKeyWithTemplate() {
        let clock = makeDate(year: 2026, month: 8, day: 6, hour: 18)
        let template = LifeTask(
            id: "tmpl-gym",
            title: "Gym",
            recurrence: .daily,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        let legacy = LifeTask(
            id: "gym-legacy-clock",
            title: "Gym",
            status: .pending,
            scheduledTime: clock,
            recurrence: .daily,
            userId: "user-1"
        )

        XCTAssertEqual(
            TaskScheduleQuery.seriesKey(for: legacy),
            TaskScheduleQuery.seriesKey(for: template)
        )
    }




    func testUniqueActiveTasksDedupesSeriesAndExcludesCompletedAdhoc() {
        let today = makeDate(year: 2026, month: 8, day: 6)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let template = LifeTask(
            id: "tmpl-gym",
            title: "Gym",
            recurrence: .daily,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        let gymToday = LifeTask(
            id: "gym-today",
            title: "Gym",
            status: .pending,
            scheduledDate: today,
            parentTaskId: template.id,
            userId: "user-1"
        )
        let gymTomorrow = LifeTask(
            id: "gym-tomorrow",
            title: "Gym",
            status: .pending,
            scheduledDate: tomorrow,
            parentTaskId: template.id,
            userId: "user-1"
        )
        let backlog = LifeTask(
            id: "backlog-1",
            title: "Call dentist",
            status: .pending,
            userId: "user-1"
        )
        let completedAdhoc = LifeTask(
            id: "done-1",
            title: "Buy milk",
            status: .completed,
            scheduledDate: today,
            completedAt: today,
            userId: "user-1"
        )
        let active = [gymToday, gymTomorrow, backlog]
        let context = active + [template, completedAdhoc]

        let unique = TaskScheduleQuery.uniqueActiveTasks(
            from: active,
            context: context,
            calendar: calendar,
            referenceDate: today
        )

        XCTAssertEqual(unique.count, 2)
        XCTAssertTrue(unique.contains(where: { $0.id == gymToday.id }))
        XCTAssertTrue(unique.contains(where: { $0.id == backlog.id }))
        XCTAssertFalse(unique.contains(where: { $0.id == gymTomorrow.id }))
        XCTAssertFalse(unique.contains(where: { $0.id == completedAdhoc.id }))
        XCTAssertFalse(unique.contains(where: { $0.id == template.id }))
    }

    func testOverdueOneOffIsActionableOnQueriedToday() {
        let today = makeDate(year: 2026, month: 7, day: 31, hour: 12)
        let yesterday = makeDate(year: 2026, month: 7, day: 30)
        let task = LifeTask(
            id: "overdue-one-off",
            title: "Pay invoice",
            status: .pending,
            scheduledDate: yesterday,
            scheduledTime: makeDate(year: 2026, month: 7, day: 30, hour: 9),
            userId: "user-1"
        )

        XCTAssertTrue(task.isOverdueOneOffCarryForward(calendar: calendar, referenceDate: today))
        XCTAssertTrue(
            TaskRecurrenceEngine.isActionableToday(task, in: [task], calendar: calendar, referenceDate: today)
        )
        XCTAssertFalse(
            TaskRecurrenceEngine.isActionableTomorrow(task, in: [task], calendar: calendar, referenceDate: today)
        )
    }

    func testPastDeadlineDoesNotStealFutureDatedOneOffOntoToday() {
        let today = makeDate(year: 2026, month: 7, day: 31, hour: 12)
        let tomorrow = makeDate(year: 2026, month: 8, day: 1)
        let pastDeadline = makeDate(year: 2026, month: 7, day: 30, hour: 18)
        let task = LifeTask(
            id: "future-one-off",
            title: "Submit report",
            status: .pending,
            deadline: pastDeadline,
            scheduledDate: tomorrow,
            scheduledTime: makeDate(year: 2026, month: 8, day: 1, hour: 10),
            userId: "user-1"
        )

        XCTAssertTrue(task.isOverdue(calendar: calendar, referenceDate: today))
        XCTAssertFalse(task.isOverdueOneOffCarryForward(calendar: calendar, referenceDate: today))
        XCTAssertFalse(
            TaskRecurrenceEngine.isActionableToday(task, in: [task], calendar: calendar, referenceDate: today)
        )
        XCTAssertTrue(
            TaskRecurrenceEngine.isActionableTomorrow(task, in: [task], calendar: calendar, referenceDate: today)
        )

        let unique = TaskScheduleQuery.uniqueActiveTasks(
            from: [task],
            context: [task],
            calendar: calendar,
            referenceDate: today
        )
        XCTAssertEqual(unique.map(\.id), [task.id])
        XCTAssertFalse(
            TaskScheduleQuery.tasksForDay(
                from: [task],
                allTasks: [task],
                day: today,
                calendar: calendar,
                referenceDate: today
            ).contains(where: { $0.id == task.id })
        )
        XCTAssertTrue(
            TaskScheduleQuery.tasksForDay(
                from: [task],
                allTasks: [task],
                day: tomorrow,
                calendar: calendar,
                referenceDate: today
            ).contains(where: { $0.id == task.id })
        )
    }

    func testReconcilePolicyDoesNotStealFutureDatedOneOffOntoToday() {
        let today = makeDate(year: 2026, month: 7, day: 31, hour: 12)
        let tomorrow = makeDate(year: 2026, month: 8, day: 1)
        let pastDeadline = makeDate(year: 2026, month: 7, day: 30, hour: 18)
        let overdueYesterday = LifeTask(
            id: "overdue-unslotted",
            title: "Pay invoice",
            status: .pending,
            scheduledDate: makeDate(year: 2026, month: 7, day: 30),
            userId: "user-1"
        )
        let futureDated = LifeTask(
            id: "future-one-off",
            title: "Submit report",
            status: .pending,
            deadline: pastDeadline,
            scheduledDate: tomorrow,
            userId: "user-1"
        )

        XCTAssertTrue(
            ReconcilePolicy.needsFullReplan(
                ReconcilePolicy.Input(tasks: [overdueYesterday], day: today, now: today),
                calendar: calendar
            )
        )
        XCTAssertFalse(
            ReconcilePolicy.needsFullReplan(
                ReconcilePolicy.Input(tasks: [overdueYesterday], day: tomorrow, now: today),
                calendar: calendar
            )
        )
        XCTAssertFalse(
            ReconcilePolicy.needsFullReplan(
                ReconcilePolicy.Input(tasks: [futureDated], day: today, now: today),
                calendar: calendar
            )
        )
    }

    func testUnscheduledBacklogStaysOffTimelineAndDoesNotSkipMaterialization() {
        let today = makeDate(year: 2026, month: 7, day: 31, hour: 12)
        let backlog = LifeTask(
            id: "backlog-plan",
            title: "Plan my day",
            status: .pending,
            tags: ["onboarding", "flexible"],
            schedulingMode: .flexible,
            userId: "user-1"
        )
        let template = LifeTask(
            id: "gym-template",
            title: "Gym",
            scheduledTime: makeDate(year: 2026, month: 7, day: 31, hour: 18, minute: 15),
            recurrence: .daily,
            schedulingMode: .fixedTime,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        let sameTitleBacklog = LifeTask(
            id: "gym-backlog",
            title: "Gym",
            status: .pending,
            schedulingMode: .flexible,
            userId: "user-1"
        )

        XCTAssertFalse(
            TaskScheduleQuery.tasksForDay(
                from: [backlog],
                allTasks: [backlog],
                day: today,
                calendar: calendar,
                referenceDate: today
            ).contains(where: { $0.id == backlog.id })
        )
        XCTAssertFalse(
            ReconcilePolicy.needsFullReplan(
                ReconcilePolicy.Input(tasks: [backlog], day: today, now: today),
                calendar: calendar
            )
        )
        XCTAssertFalse(
            TaskSeriesResolver.shouldSkipMaterialization(
                for: template,
                on: today,
                in: [template, sameTitleBacklog],
                calendar: calendar
            )
        )
    }

    func testDeadlineOnlyOverdueOneOffStaysOnTodayTimeline() {
        let today = makeDate(year: 2026, month: 7, day: 31, hour: 12)
        let pastDeadline = makeDate(year: 2026, month: 7, day: 30, hour: 18)
        let task = LifeTask(
            id: "deadline-only",
            title: "Pay invoice",
            status: .pending,
            deadline: pastDeadline,
            userId: "user-1"
        )

        XCTAssertTrue(task.isOverdueOneOffCarryForward(calendar: calendar, referenceDate: today))
        XCTAssertTrue(
            TaskScheduleQuery.tasksForDay(
                from: [task],
                allTasks: [task],
                day: today,
                calendar: calendar,
                referenceDate: today
            ).contains(where: { $0.id == task.id })
        )
        XCTAssertTrue(
            TaskScheduleQuery.activeTasksForToday(
                from: [task],
                calendar: calendar,
                referenceDate: today
            ).contains(where: { $0.id == task.id })
        )
    }

    func testUnscheduledBacklogExcludedFromTodayList() {
        let today = makeDate(year: 2026, month: 7, day: 31, hour: 12)
        let backlog = LifeTask(
            id: "backlog-plan",
            title: "Plan my day",
            status: .pending,
            tags: ["onboarding", "flexible"],
            schedulingMode: .flexible,
            userId: "user-1"
        )
        let timeOnlyToday = LifeTask(
            id: "time-only-today",
            title: "Call dentist",
            status: .pending,
            scheduledTime: makeDate(year: 2026, month: 7, day: 31, hour: 10),
            userId: "user-1"
        )
        let futureDated = LifeTask(
            id: "future-one-off",
            title: "Submit report",
            status: .pending,
            deadline: makeDate(year: 2026, month: 7, day: 30, hour: 18),
            scheduledDate: makeDate(year: 2026, month: 8, day: 1),
            userId: "user-1"
        )

        let todayList = TaskScheduleQuery.activeTasksForToday(
            from: [backlog, timeOnlyToday, futureDated],
            calendar: calendar,
            referenceDate: today
        )
        XCTAssertFalse(todayList.contains(where: { $0.id == backlog.id }))
        XCTAssertTrue(todayList.contains(where: { $0.id == timeOnlyToday.id }))
        XCTAssertFalse(todayList.contains(where: { $0.id == futureDated.id }))
        XCTAssertTrue(backlog.isActiveBacklog(calendar: calendar, referenceDate: today))
    }

    func testDeadlineOnlyDueTodayAppearsOnTodayListAndTimeline() {
        let today = makeDate(year: 2026, month: 7, day: 31, hour: 10)
        let deadline = makeDate(year: 2026, month: 7, day: 31, hour: 18)
        let task = LifeTask(
            id: "deadline-due-today",
            title: "File taxes",
            status: .pending,
            deadline: deadline,
            userId: "user-1"
        )

        XCTAssertTrue(task.isDeadlineOnlyDue(on: today, calendar: calendar))
        XCTAssertFalse(task.isOverdue(calendar: calendar, referenceDate: today))
        XCTAssertFalse(task.isActiveBacklog(calendar: calendar, referenceDate: today))
        XCTAssertTrue(
            TaskRecurrenceEngine.isActionableToday(task, in: [task], calendar: calendar, referenceDate: today)
        )
        XCTAssertTrue(
            TaskScheduleQuery.activeTasksForToday(
                from: [task],
                calendar: calendar,
                referenceDate: today
            ).contains(where: { $0.id == task.id })
        )
        XCTAssertTrue(
            TaskScheduleQuery.tasksForDay(
                from: [task],
                allTasks: [task],
                day: today,
                calendar: calendar,
                referenceDate: today
            ).contains(where: { $0.id == task.id })
        )
        XCTAssertTrue(
            ReconcilePolicy.needsFullReplan(
                ReconcilePolicy.Input(tasks: [task], day: today, now: today),
                calendar: calendar
            )
        )
    }

    func testTomorrowDeadlineOnlyIsActionableTomorrowNotToday() {
        let today = makeDate(year: 2026, month: 7, day: 31, hour: 12)
        let tomorrowDeadline = makeDate(year: 2026, month: 8, day: 1, hour: 18)
        let task = LifeTask(
            id: "deadline-tomorrow",
            title: "Submit invoice",
            status: .pending,
            deadline: tomorrowDeadline,
            userId: "user-1"
        )

        XCTAssertFalse(
            TaskRecurrenceEngine.isActionableToday(task, in: [task], calendar: calendar, referenceDate: today)
        )
        XCTAssertTrue(
            TaskRecurrenceEngine.isActionableTomorrow(task, in: [task], calendar: calendar, referenceDate: today)
        )
        XCTAssertFalse(task.isUpcoming(allTasks: [task], calendar: calendar, referenceDate: today))
        XCTAssertFalse(task.isActiveBacklog(calendar: calendar, referenceDate: today))
    }

    func testFutureDeadlineOnlyIsUpcomingNotBacklog() {
        let today = makeDate(year: 2026, month: 7, day: 31, hour: 12)
        let laterDeadline = makeDate(year: 2026, month: 8, day: 4, hour: 18)
        let task = LifeTask(
            id: "deadline-later",
            title: "Renew license",
            status: .pending,
            deadline: laterDeadline,
            userId: "user-1"
        )

        XCTAssertFalse(
            TaskRecurrenceEngine.isActionableToday(task, in: [task], calendar: calendar, referenceDate: today)
        )
        XCTAssertFalse(
            TaskRecurrenceEngine.isActionableTomorrow(task, in: [task], calendar: calendar, referenceDate: today)
        )
        XCTAssertTrue(task.isUpcoming(allTasks: [task], calendar: calendar, referenceDate: today))
        XCTAssertFalse(task.isActiveBacklog(calendar: calendar, referenceDate: today))
    }

    func testFutureTimeOnlyOneOffIsNotOverdueCarryForward() {
        let today = makeDate(year: 2026, month: 7, day: 31, hour: 12)
        let tomorrow = makeDate(year: 2026, month: 8, day: 1, hour: 9)
        let pastDeadline = makeDate(year: 2026, month: 7, day: 30, hour: 18)
        let task = LifeTask(
            id: "time-only-tomorrow",
            title: "Call dentist",
            status: .pending,
            deadline: pastDeadline,
            scheduledTime: tomorrow,
            userId: "user-1"
        )

        XCTAssertFalse(task.isOverdueOneOffCarryForward(calendar: calendar, referenceDate: today))
        XCTAssertFalse(
            TaskRecurrenceEngine.isActionableToday(task, in: [task], calendar: calendar, referenceDate: today)
        )
        XCTAssertFalse(
            TaskScheduleQuery.tasksForDay(
                from: [task],
                allTasks: [task],
                day: today,
                calendar: calendar,
                referenceDate: today
            ).contains(where: { $0.id == task.id })
        )
        XCTAssertTrue(
            TaskRecurrenceEngine.isActionable(
                on: tomorrow,
                task: task,
                in: [task],
                calendar: calendar,
                referenceDate: today
            )
        )
    }

    func testFutureTimeOnlyClockIsUpcomingNotBacklog() {
        let today = makeDate(year: 2026, month: 7, day: 31, hour: 12)
        let laterClock = makeDate(year: 2026, month: 8, day: 4, hour: 18)
        let task = LifeTask(
            id: "time-only-later",
            title: "Dinner reservation",
            status: .pending,
            scheduledTime: laterClock,
            schedulingMode: .fixedTime,
            userId: "user-1"
        )

        XCTAssertFalse(
            TaskRecurrenceEngine.isActionableToday(task, in: [task], calendar: calendar, referenceDate: today)
        )
        XCTAssertFalse(
            TaskRecurrenceEngine.isActionableTomorrow(task, in: [task], calendar: calendar, referenceDate: today)
        )
        XCTAssertTrue(task.isUpcoming(allTasks: [task], calendar: calendar, referenceDate: today))
        XCTAssertFalse(task.isActiveBacklog(calendar: calendar, referenceDate: today))
        XCTAssertFalse(task.isScheduledThisWeek(calendar: calendar, referenceDate: today))
        XCTAssertTrue(
            TaskScheduleQuery.uniqueActiveTasks(
                from: [task],
                context: [task],
                calendar: calendar,
                referenceDate: today
            ).contains(where: { $0.id == task.id })
        )
    }

    func testTomorrowTimeOnlyClockIsScheduledThisWeekNotUpcoming() {
        let today = makeDate(year: 2026, month: 7, day: 31, hour: 12)
        let tomorrowClock = makeDate(year: 2026, month: 8, day: 1, hour: 21)
        let task = LifeTask(
            id: "time-only-tomorrow-week",
            title: "Gym",
            status: .pending,
            scheduledTime: tomorrowClock,
            schedulingMode: .fixedTime,
            userId: "user-1"
        )

        XCTAssertFalse(task.isUpcoming(allTasks: [task], calendar: calendar, referenceDate: today))
        XCTAssertTrue(task.isScheduledThisWeek(calendar: calendar, referenceDate: today))
        XCTAssertFalse(task.isScheduledTask(allTasks: [task], calendar: calendar, referenceDate: today))
    }

    func testTimeOnlyRecurringMasterIsActionableOnClockDay() {
        let today = makeDate(year: 2026, month: 7, day: 31, hour: 12)
        let clock = makeDate(year: 2026, month: 7, day: 31, hour: 21)
        let task = LifeTask(
            id: "time-only-recurring",
            title: "Evening stretch",
            status: .pending,
            scheduledTime: clock,
            recurrence: .daily,
            schedulingMode: .fixedTime,
            userId: "user-1"
        )

        XCTAssertFalse(TaskRecurrenceEngine.isRecurrenceTemplate(task))
        XCTAssertTrue(
            TaskRecurrenceEngine.isActionableToday(task, in: [task], calendar: calendar, referenceDate: today)
        )
        XCTAssertTrue(
            TaskScheduleQuery.activeTasksForToday(
                from: [task],
                calendar: calendar,
                referenceDate: today
            ).contains(where: { $0.id == task.id })
        )
        XCTAssertTrue(
            TaskRecurrenceEngine.missingOccurrences(for: [task], on: today, calendar: calendar).isEmpty,
            "A clocked recurring row is already today's occurrence, not a dateless template"
        )
    }

    func testTimeOnlyLegacyRecurringNeedsNormalization() {
        let clock = makeDate(year: 2026, month: 7, day: 31, hour: 21)
        let task = LifeTask(
            id: "legacy-clocked",
            title: "Evening stretch",
            status: .pending,
            scheduledTime: clock,
            recurrence: .daily,
            schedulingMode: .fixedTime,
            userId: "user-1"
        )

        XCTAssertTrue(TaskRecurrenceEngine.needsLegacyNormalization(task))
        let split = TaskRecurrenceEngine.normalizeLegacyRecurringTask(task)
        XCTAssertTrue(split.template.isRecurrenceTemplate == true)
        XCTAssertNil(split.template.scheduledDate)
        XCTAssertEqual(split.template.scheduledTime, clock)
        XCTAssertEqual(split.occurrence.parentTaskId, split.template.id)
        XCTAssertEqual(split.occurrence.scheduledTime, clock)
        XCTAssertEqual(split.occurrence.recurrenceRule, .none)
    }


    func testTimeOnlyWeekdayOccurrenceIsNotActionableOnSunday() {
        let sunday = makeDate(year: 2026, month: 8, day: 2, hour: 10)
        let clock = makeDate(year: 2026, month: 8, day: 2, hour: 8, minute: 30)
        let task = LifeTask(
            id: "time-only-weekday",
            title: "Standup",
            status: .pending,
            scheduledTime: clock,
            recurrence: .weekdays,
            schedulingMode: .fixedTime,
            userId: "user-1"
        )

        XCTAssertFalse(
            TaskRecurrenceEngine.isActionableToday(task, in: [task], calendar: calendar, referenceDate: sunday)
        )
        XCTAssertFalse(
            TaskScheduleQuery.activeTasksForToday(
                from: [task],
                calendar: calendar,
                referenceDate: sunday
            ).contains(where: { $0.id == task.id })
        )
    }

    func testTimeOnlyDailyAnchorUsesClockDayNotLaterCreatedAt() {
        let clock = makeDate(year: 2026, month: 7, day: 31, hour: 21)
        let createdLater = makeDate(year: 2026, month: 8, day: 2, hour: 9)
        let task = LifeTask(
            id: "time-only-daily-backdated",
            title: "Evening stretch",
            status: .pending,
            scheduledTime: clock,
            recurrence: .daily,
            schedulingMode: .fixedTime,
            createdAt: createdLater,
            userId: "user-1"
        )

        XCTAssertEqual(
            TaskRecurrenceEngine.recurrenceAnchor(for: task, source: task, in: [task], calendar: calendar),
            calendar.startOfDay(for: clock)
        )
        XCTAssertTrue(
            TaskRecurrenceEngine.isActionableToday(
                task,
                in: [task],
                calendar: calendar,
                referenceDate: clock
            )
        )
    }

    func testTimeOnlyFutureClockDoesNotOccurOnEarlierCreatedDay() {
        let created = makeDate(year: 2026, month: 8, day: 7, hour: 9)
        let clock = makeDate(year: 2026, month: 8, day: 8, hour: 21, minute: 30)
        let task = LifeTask(
            id: "time-only-future-clock",
            title: "Dinner",
            status: .pending,
            scheduledTime: clock,
            recurrence: .daily,
            schedulingMode: .fixedTime,
            createdAt: created,
            userId: "user-1"
        )

        XCTAssertFalse(
            task.recurrenceOccurs(on: created, calendar: calendar),
            "A future time-only clock must not match the earlier created day"
        )
        XCTAssertTrue(task.recurrenceOccurs(on: clock, calendar: calendar))
    }





    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        TestCalendarFixtures.date(year: year, month: month, day: day, hour: hour, minute: minute)
    }
}
