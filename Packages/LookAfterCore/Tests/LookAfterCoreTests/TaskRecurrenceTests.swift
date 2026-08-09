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

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        TestCalendarFixtures.date(year: year, month: month, day: day, hour: hour, minute: minute)
    }
}
