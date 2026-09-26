import XCTest
@testable import LookAfterCore

final class ScheduleProactiveAnalyzerTests: XCTestCase {
    private let calendar = TestCalendarFixtures.calendar

    func testWorkOnRestDayFlagsOfficeTaskOnSunday() {
        let sunday = TestCalendarFixtures.date(year: 2026, month: 8, day: 2, hour: 10)
        let task = LifeTask(
            title: "Office standup",
            lifeArea: .work,
            scheduledDate: sunday,
            userId: "user-1"
        )
        let input = ScheduleProactiveAnalyzer.Input(
            tasks: [task],
            referenceDate: sunday,
            now: sunday,
            calendar: calendar
        )

        let suggestions = ScheduleProactiveAnalyzer.analyze(input)

        XCTAssertTrue(suggestions.contains { $0.kind == .workOnRestDay })
    }

    func testFixedTaskMissingTimeSurfacesSuggestion() {
        let today = TestCalendarFixtures.today
        var task = LifeTask(
            title: "Dentist",
            scheduledDate: today,
            schedulingMode: .fixedTime,
            userId: "user-1"
        )
        task.scheduledTime = nil

        let input = ScheduleProactiveAnalyzer.Input(
            tasks: [task],
            referenceDate: today,
            now: today,
            calendar: calendar
        )

        let suggestions = ScheduleProactiveAnalyzer.analyze(input)

        XCTAssertTrue(suggestions.contains { $0.kind == ScheduleProactiveSuggestion.Kind.fixedTaskMissingTime })
    }

    func testMorningPlanReviewOnEarlyOpen() {
        let morning = TestCalendarFixtures.date(year: 2026, month: 7, day: 31, hour: 8)
        let task = LifeTask(title: "Email", scheduledDate: morning, userId: "user-1")
        let input = ScheduleProactiveAnalyzer.Input(
            tasks: [task],
            referenceDate: morning,
            now: morning,
            calendar: calendar
        )

        let suggestions = ScheduleProactiveAnalyzer.analyze(input)

        XCTAssertTrue(suggestions.contains { $0.kind == .morningPlanReview })
    }

    func testCarryForwardClockIsNotPastDueStillToday() {
        let today = TestCalendarFixtures.date(year: 2026, month: 7, day: 31, hour: 10)
        let yesterdayClock = TestCalendarFixtures.date(year: 2026, month: 7, day: 30, hour: 9)
        let task = LifeTask(
            id: "carry-forward",
            title: "Call dentist",
            status: .pending,
            scheduledTime: yesterdayClock,
            schedulingMode: .fixedTime,
            userId: "user-1"
        )
        let input = ScheduleProactiveAnalyzer.Input(
            tasks: [task],
            referenceDate: today,
            now: today,
            calendar: calendar
        )

        let suggestions = ScheduleProactiveAnalyzer.analyze(input)

        XCTAssertFalse(suggestions.contains { $0.kind == .pastDueStillToday })
    }

    func testTodayPastClockStillFlagsPastDue() {
        let now = TestCalendarFixtures.date(year: 2026, month: 7, day: 31, hour: 11)
        let morning = TestCalendarFixtures.date(year: 2026, month: 7, day: 31, hour: 9)
        let task = LifeTask(
            id: "today-past",
            title: "Standup",
            status: .pending,
            scheduledDate: morning,
            scheduledTime: morning,
            schedulingMode: .fixedTime,
            userId: "user-1"
        )
        let input = ScheduleProactiveAnalyzer.Input(
            tasks: [task],
            referenceDate: now,
            now: now,
            calendar: calendar
        )

        let suggestions = ScheduleProactiveAnalyzer.analyze(input)

        XCTAssertTrue(suggestions.contains { $0.kind == .pastDueStillToday })
    }

    func testTimeOnlyDuplicateBlocksFlagDuplicateSeries() {
        let morning = TestCalendarFixtures.date(year: 2026, month: 7, day: 31, hour: 8)
        let evening = TestCalendarFixtures.date(year: 2026, month: 7, day: 31, hour: 20)
        let first = LifeTask(
            id: "brush-am",
            title: "Brush teeth",
            status: .pending,
            scheduledTime: morning,
            userId: "user-1"
        )
        let second = LifeTask(
            id: "brush-pm",
            title: "Brush teeth",
            status: .pending,
            scheduledTime: evening,
            userId: "user-1"
        )
        let input = ScheduleProactiveAnalyzer.Input(
            tasks: [first, second],
            referenceDate: morning,
            now: morning,
            calendar: calendar
        )

        let suggestions = ScheduleProactiveAnalyzer.analyze(input)

        XCTAssertTrue(suggestions.contains { $0.kind == .duplicateSeries })
    }



}
