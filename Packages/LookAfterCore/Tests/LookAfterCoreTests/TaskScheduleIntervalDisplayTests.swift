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
