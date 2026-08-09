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
}
