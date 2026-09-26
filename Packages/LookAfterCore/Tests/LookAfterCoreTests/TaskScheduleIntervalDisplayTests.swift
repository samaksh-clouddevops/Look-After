import XCTest
@testable import LookAfterCore

final class TaskScheduleIntervalDisplayTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testFlexibleTaskWithWorkBlockEndShowsEstimatedDuration() {
        let day = makeDate(year: 2026, month: 8, day: 4, hour: 0)
        let start = makeDate(year: 2026, month: 8, day: 4, hour: 8, minute: 30)
        let end = makeDate(year: 2026, month: 8, day: 4, hour: 20, minute: 0)
        let task = LifeTask(
            title: "Review notes",
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: start,
            schedulingMode: .flexible,
            scheduledEndTime: end
        )

        XCTAssertEqual(
            TaskScheduleInterval.displayDurationMinutes(for: task, on: day, calendar: calendar),
            45
        )
    }

    func testFixedWorkBlockStillUsesFullWindowDuration() {
        let day = makeDate(year: 2026, month: 8, day: 4, hour: 0)
        let start = makeDate(year: 2026, month: 8, day: 4, hour: 8, minute: 30)
        let end = makeDate(year: 2026, month: 8, day: 4, hour: 17, minute: 30)
        let task = LifeTask(
            title: "Office",
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: start,
            schedulingMode: .fixedTime,
            scheduledEndTime: end
        )

        XCTAssertEqual(
            TaskScheduleInterval.displayDurationMinutes(for: task, on: day, calendar: calendar),
            540
        )
    }

    func testDateOnlyFlexibleUsesEstimatedMinutes() {
        let day = makeDate(year: 2026, month: 8, day: 5, hour: 0)
        let task = LifeTask(
            title: "Morning review",
            estimatedMinutes: 10,
            scheduledDate: day,
            schedulingMode: .flexible
        )

        XCTAssertEqual(
            TaskScheduleInterval.displayDurationMinutes(for: task, on: day, calendar: calendar),
            10
        )
    }

    func testFlexibleGlanceLabelAvoidsMidnightDayEndRange() {
        let day = makeDate(year: 2026, month: 9, day: 9, hour: 0)
        let event = LifeTimelineEvent(
            id: "task-morning-review",
            kind: .work,
            title: "Morning review",
            subtitle: "Flexible today",
            date: day,
            estimatedMinutes: 10,
            isFixed: false,
            scheduleKind: .flexibleDay
        )

        XCTAssertEqual(event.scheduleRangeLabel, "Flexible today · 10m")
        XCTAssertFalse(event.isImportantCommitment)
        XCTAssertFalse(event.scheduleRangeLabel.contains("12:00 AM"))
    }

    func testMidnightPlaceholderOnOtherDayIsNotFlexibleToday() {
        let today = makeDate(year: 2026, month: 8, day: 4, hour: 0)
        let tomorrow = makeDate(year: 2026, month: 8, day: 5, hour: 0)
        let task = LifeTask(
            title: "Tomorrow errand",
            scheduledDate: tomorrow,
            scheduledTime: tomorrow,
            schedulingMode: .flexible
        )

        XCTAssertTrue(TaskScheduleInterval.isPlaceholderMidnightSchedule(for: task, calendar: calendar))
        XCTAssertFalse(TaskScheduleInterval.isFlexibleDaySchedule(for: task, on: today, calendar: calendar))
        XCTAssertTrue(TaskScheduleInterval.isFlexibleDaySchedule(for: task, on: tomorrow, calendar: calendar))
        XCTAssertEqual(
            TaskScheduleInterval.displaySchedule(for: task, on: today, calendar: calendar),
            .noSchedule
        )
        XCTAssertEqual(
            TaskScheduleInterval.displaySchedule(for: task, on: tomorrow, calendar: calendar),
            .unslottedFlexible
        )
    }

    func testUnscheduledBacklogDisplayIsNoSchedule() {
        let today = makeDate(year: 2026, month: 8, day: 4, hour: 0)
        let task = LifeTask(
            title: "Someday inbox",
            schedulingMode: .flexible
        )

        XCTAssertFalse(TaskScheduleInterval.isFlexibleDaySchedule(for: task, on: today, calendar: calendar))
        XCTAssertEqual(
            TaskScheduleInterval.displaySchedule(for: task, on: today, calendar: calendar),
            .noSchedule
        )
    }

    func testDeadlineOnlyDueTodayDisplayIsFlexible() {
        let today = makeDate(year: 2026, month: 8, day: 4, hour: 10)
        let task = LifeTask(
            title: "File taxes",
            deadline: makeDate(year: 2026, month: 8, day: 4, hour: 18),
            schedulingMode: .flexible
        )

        XCTAssertTrue(TaskScheduleInterval.isFlexibleDaySchedule(for: task, on: today, calendar: calendar))
        XCTAssertEqual(
            TaskScheduleInterval.displaySchedule(for: task, on: today, calendar: calendar),
            .unslottedFlexible
        )
    }

    func testTimeOnlyClockOnQueriedDayBuildsWindow() {
        let day = makeDate(year: 2026, month: 8, day: 7, hour: 0)
        let clock = makeDate(year: 2026, month: 8, day: 7, hour: 19, minute: 30)
        let task = LifeTask(
            id: "dinner-time-only",
            title: "Dinner",
            estimatedMinutes: 45,
            scheduledTime: clock,
            schedulingMode: .fixedTime,
            userId: "user-1"
        )

        let window = TaskScheduleInterval.window(for: task, on: day, calendar: calendar)
        XCTAssertEqual(window?.start, clock)
        XCTAssertTrue(TaskScheduleInterval.hasConcreteTimelineSlot(for: task, on: day, calendar: calendar))
        XCTAssertEqual(TaskScheduleInterval.timelineDisplayTime(for: task, on: day, calendar: calendar), clock)

        let tomorrow = makeDate(year: 2026, month: 8, day: 8, hour: 0)
        XCTAssertNil(TaskScheduleInterval.window(for: task, on: tomorrow, calendar: calendar))
        XCTAssertFalse(TaskScheduleInterval.hasConcreteTimelineSlot(for: task, on: tomorrow, calendar: calendar))
    }

    func testTimeOnlyClockDoesNotResolveOntoAnotherDay() {
        let today = makeDate(year: 2026, month: 8, day: 7, hour: 0)
        let tomorrow = makeDate(year: 2026, month: 8, day: 8, hour: 0)
        let clock = makeDate(year: 2026, month: 8, day: 8, hour: 19, minute: 30)
        let task = LifeTask(
            id: "tomorrow-dinner",
            title: "Dinner",
            estimatedMinutes: 45,
            scheduledTime: clock,
            schedulingMode: .fixedTime,
            userId: "user-1"
        )

        XCTAssertNil(TaskScheduleInterval.resolvedStart(for: task, on: today, calendar: calendar))
        XCTAssertNil(TaskScheduleInterval.resolvedEnd(for: task, on: today, calendar: calendar))
        XCTAssertEqual(
            TaskScheduleInterval.displaySchedule(for: task, on: today, calendar: calendar),
            .noSchedule
        )
        XCTAssertEqual(
            TaskScheduleInterval.resolvedStart(for: task, on: tomorrow, calendar: calendar),
            clock
        )
    }


}

final class PreWindowFitAnalyzerTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testDetectsOvercommitmentBeforeFixedWork() {
        let now = makeDate(year: 2026, month: 8, day: 7, hour: 8, minute: 40)
        let day = calendar.startOfDay(for: now)
        let workStart = makeDate(year: 2026, month: 8, day: 7, hour: 9, minute: 0)
        let flexStart = makeDate(year: 2026, month: 8, day: 7, hour: 8, minute: 45)

        let work = LifeTask(
            title: "Office",
            estimatedMinutes: 480,
            scheduledDate: day,
            scheduledTime: workStart,
            schedulingMode: .fixedTime,
            scheduledEndTime: makeDate(year: 2026, month: 8, day: 7, hour: 17, minute: 30)
        )
        let flexA = LifeTask(
            title: "Email",
            estimatedMinutes: 30,
            scheduledDate: day,
            scheduledTime: flexStart,
            schedulingMode: .flexible,
            scheduledEndTime: flexStart.addingTimeInterval(30 * 60)
        )
        let flexB = LifeTask(
            title: "Prep deck",
            estimatedMinutes: 25,
            scheduledDate: day,
            scheduledTime: flexStart.addingTimeInterval(35 * 60),
            schedulingMode: .flexible,
            scheduledEndTime: flexStart.addingTimeInterval(60 * 60)
        )

        let result = PreWindowFitAnalyzer.analyze(
            tasks: [work, flexA, flexB],
            now: now,
            horizonMinutes: 120,
            calendar: calendar
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.isOvercommitted)
        XCTAssertEqual(result!.anchor.minutesUntilStart, 20)
        XCTAssertGreaterThan(result!.requiredMinutes, result!.availableMinutes)
    }
}
