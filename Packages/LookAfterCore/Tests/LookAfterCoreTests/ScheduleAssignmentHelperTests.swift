import XCTest
@testable import LookAfterCore

final class ScheduleAssignmentHelperTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testSecondTaskShiftsWhenSameStartProposed() {
        let day = makeDate(year: 2026, month: 8, day: 4)
        let ninePM = makeDate(year: 2026, month: 8, day: 4, hour: 21, minute: 0)

        let guitar = LifeTask(
            title: "Guitar",
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: ninePM,
            schedulingMode: .fixedTime
        )
        var songwriting = LifeTask(
            title: "Songwriting",
            estimatedMinutes: 45,
            scheduledDate: day,
            schedulingMode: .flexible
        )

        let resolved = ScheduleAssignmentHelper.scheduledTimeAvoidingOverlap(
            proposed: ninePM,
            task: songwriting,
            existingTasks: [guitar],
            on: day,
            calendar: calendar
        )

        ScheduleAssignmentHelper.applySchedule(to: &songwriting, start: resolved, on: day, calendar: calendar)

        let guitarWindow = TaskScheduleInterval.window(for: guitar, on: day, calendar: calendar)!
        let songwritingWindow = TaskScheduleInterval.window(for: songwriting, on: day, calendar: calendar)!
        XCTAssertFalse(guitarWindow.overlaps(songwritingWindow))
        XCTAssertGreaterThan(songwritingWindow.start, guitarWindow.start)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
