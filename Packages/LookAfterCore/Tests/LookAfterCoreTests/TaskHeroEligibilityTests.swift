import XCTest
@testable import LookAfterCore

final class TaskHeroEligibilityTests: XCTestCase {

    private var calendar: Calendar { TestCalendarFixtures.calendar }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        TestCalendarFixtures.date(year: year, month: month, day: day, hour: hour, minute: minute)
    }

    func testMorningWorkNotEligibleAtElevenPM() {
        let day = makeDate(year: 2026, month: 8, day: 2, hour: 0)
        let workStart = makeDate(year: 2026, month: 8, day: 2, hour: 8, minute: 30)
        let now = makeDate(year: 2026, month: 8, day: 2, hour: 23)

        let work = LifeTask(
            title: "Work",
            lifeArea: .work,
            status: .pending,
            estimatedMinutes: 51,
            scheduledDate: day,
            scheduledTime: workStart,
            schedulingMode: .fixedTime
        )

        XCTAssertEqual(TaskHeroEligibility.status(for: work, now: now, calendar: calendar), .pastWindow)
        XCTAssertFalse(TaskHeroEligibility.isEligible(for: work, now: now, calendar: calendar))
    }

    func testEveningCreativeTaskEligibleDuringWindow() {
        let day = makeDate(year: 2026, month: 8, day: 2, hour: 0)
        let musicStart = makeDate(year: 2026, month: 8, day: 2, hour: 21)
        let now = makeDate(year: 2026, month: 8, day: 2, hour: 22)

        let music = LifeTask(
            title: "Music production",
            lifeArea: .creativity,
            estimatedMinutes: 90,
            scheduledDate: day,
            scheduledTime: musicStart,
            schedulingMode: .fixedTime
        )

        XCTAssertEqual(TaskHeroEligibility.status(for: music, now: now, calendar: calendar), .eligible)
        XCTAssertTrue(TaskHeroEligibility.isEligible(for: music, now: now, calendar: calendar))
    }

    func testUpcomingGymWithinGraceIsEligible() {
        let day = makeDate(year: 2026, month: 8, day: 2, hour: 0)
        let gymStart = makeDate(year: 2026, month: 8, day: 2, hour: 18, minute: 30)
        let now = makeDate(year: 2026, month: 8, day: 2, hour: 17, minute: 45)

        let gym = LifeTask(
            title: "Gym",
            lifeArea: .health,
            estimatedMinutes: 90,
            scheduledDate: day,
            scheduledTime: gymStart,
            schedulingMode: .fixedTime
        )

        if case .upcoming(let minutes) = TaskHeroEligibility.status(for: gym, now: now, calendar: calendar) {
            XCTAssertEqual(minutes, 45)
        } else {
            XCTFail("Expected upcoming status")
        }
        XCTAssertTrue(TaskHeroEligibility.isEligible(for: gym, now: now, calendar: calendar))
    }

    func testInProgressTaskRemainsEligibleAfterWindow() {
        let day = makeDate(year: 2026, month: 8, day: 2, hour: 0)
        let workStart = makeDate(year: 2026, month: 8, day: 2, hour: 8, minute: 30)
        let now = makeDate(year: 2026, month: 8, day: 2, hour: 23)

        let work = LifeTask(
            title: "Work",
            status: .inProgress,
            estimatedMinutes: 51,
            scheduledDate: day,
            scheduledTime: workStart,
            schedulingMode: .fixedTime
        )

        XCTAssertEqual(TaskHeroEligibility.status(for: work, now: now, calendar: calendar), .inProgress)
        XCTAssertTrue(TaskHeroEligibility.isEligible(for: work, now: now, calendar: calendar))
    }

    func testWeekdayWorkNotEligibleOnSunday() {
        let sunday = makeDate(year: 2026, month: 8, day: 2, hour: 23)
        let workStart = makeDate(year: 2026, month: 8, day: 1, hour: 8, minute: 30)
        let template = LifeTask(
            title: "Work",
            scheduledTime: workStart,
            recurrence: .weekdays,
            schedulingMode: .fixedTime,
            userId: "user-1",
            isRecurrenceTemplate: true
        )
        let occurrence = TaskRecurrenceEngine.makeOccurrence(
            from: template,
            template: template,
            scheduledDate: makeDate(year: 2026, month: 8, day: 2, hour: 0),
            calendar: calendar
        )
        let allTasks = [template, occurrence]

        XCTAssertFalse(
            TaskHeroEligibility.isEligible(
                for: occurrence,
                now: sunday,
                calendar: calendar,
                allTasks: allTasks
            )
        )
    }

    func testUnscheduledBacklogIsNotHeroEligible() {
        let now = makeDate(year: 2026, month: 8, day: 2, hour: 10)
        let backlog = LifeTask(
            title: "Plan my day",
            status: .pending,
            schedulingMode: .flexible
        )

        XCTAssertEqual(TaskHeroEligibility.status(for: backlog, now: now, calendar: calendar), .unscheduled)
        XCTAssertFalse(TaskHeroEligibility.isEligible(for: backlog, now: now, calendar: calendar))
    }

    func testDeadlineOnlyDueTodayIsHeroEligible() {
        let now = makeDate(year: 2026, month: 8, day: 2, hour: 10)
        let task = LifeTask(
            title: "File taxes",
            status: .pending,
            deadline: makeDate(year: 2026, month: 8, day: 2, hour: 18)
        )

        XCTAssertTrue(TaskHeroEligibility.isEligible(for: task, now: now, calendar: calendar))
    }

    func testFutureDeadlineOnlyIsNotHeroEligibleToday() {
        let now = makeDate(year: 2026, month: 8, day: 2, hour: 10)
        let task = LifeTask(
            title: "Renew license",
            status: .pending,
            deadline: makeDate(year: 2026, month: 8, day: 5, hour: 18)
        )

        XCTAssertFalse(TaskHeroEligibility.isEligible(for: task, now: now, calendar: calendar))
    }

    func testOverdueOneOffWithYesterdayClockIsUnscheduledAndEligible() {
        let yesterday = makeDate(year: 2026, month: 8, day: 1, hour: 0)
        let yesterdayNine = makeDate(year: 2026, month: 8, day: 1, hour: 9)
        let now = makeDate(year: 2026, month: 8, day: 2, hour: 10)
        let task = LifeTask(
            title: "Pay the invoice",
            status: .pending,
            estimatedMinutes: 45,
            scheduledDate: yesterday,
            scheduledTime: yesterdayNine,
            userId: "user-1"
        )

        XCTAssertTrue(task.isOverdueOneOffCarryForward(calendar: calendar, referenceDate: now))
        XCTAssertEqual(TaskHeroEligibility.status(for: task, now: now, calendar: calendar), .unscheduled)
        XCTAssertTrue(TaskHeroEligibility.isEligible(for: task, now: now, calendar: calendar))
        XCTAssertFalse(TaskHeroEligibility.isPastWindow(for: task, now: now, calendar: calendar))
    }

    func testFutureDatedOneOffClockIsNotRemappedOntoToday() {
        let tomorrow = makeDate(year: 2026, month: 8, day: 3, hour: 0)
        let tomorrowTen = makeDate(year: 2026, month: 8, day: 3, hour: 10)
        let now = makeDate(year: 2026, month: 8, day: 2, hour: 9)
        let task = LifeTask(
            title: "Dentist",
            status: .pending,
            estimatedMinutes: 60,
            scheduledDate: tomorrow,
            scheduledTime: tomorrowTen,
            userId: "user-1"
        )

        XCTAssertEqual(TaskHeroEligibility.status(for: task, now: now, calendar: calendar), .unscheduled)
        XCTAssertFalse(TaskHeroEligibility.isEligible(for: task, now: now, calendar: calendar))
    }

    func testFutureTimeOnlyClockIsNotRemappedOntoToday() {
        let now = makeDate(year: 2026, month: 8, day: 2, hour: 9)
        let tomorrowClock = makeDate(year: 2026, month: 8, day: 3, hour: 21)
        let task = LifeTask(
            title: "Dinner",
            status: .pending,
            estimatedMinutes: 45,
            scheduledTime: tomorrowClock,
            schedulingMode: .fixedTime,
            userId: "user-1"
        )

        XCTAssertEqual(TaskHeroEligibility.status(for: task, now: now, calendar: calendar), .unscheduled)
        XCTAssertFalse(TaskHeroEligibility.isEligible(for: task, now: now, calendar: calendar))
        XCTAssertFalse(TaskHeroEligibility.isPastWindow(for: task, now: now, calendar: calendar))
    }

}
