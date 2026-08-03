import XCTest
@testable import LifeOSCore

final class DaySlotAllocatorTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let workHours = PlanningSchedulePolicy.WorkHours(startHour: 9, endHour: 18)

    func testSchedulesAfterFixedBlock() {
        let day = makeDate(year: 2026, month: 8, day: 4, hour: 10)
        let fixedStart = makeDate(year: 2026, month: 8, day: 4, hour: 9)
        let fixedEnd = makeDate(year: 2026, month: 8, day: 4, hour: 10)
        let fixed = LifeTask(
            title: "Standup",
            estimatedMinutes: 60,
            scheduledDate: day,
            scheduledTime: fixedStart,
            schedulingMode: .fixedTime,
            scheduledEndTime: fixedEnd
        )

        let allocations = DaySlotAllocator.allocate(
            requests: [
                DaySlotAllocator.Request(id: "new-task", estimatedMinutes: 30, priority: .high)
            ],
            existingTasks: [fixed],
            workHours: workHours,
            now: day,
            calendar: calendar
        )

        XCTAssertEqual(allocations.count, 1)
        let scheduled = allocations[0].scheduledTime
        XCTAssertGreaterThanOrEqual(scheduled, fixedEnd)
    }

    func testHigherPriorityScheduledBeforeLower() {
        let now = makeDate(year: 2026, month: 8, day: 4, hour: 10)
        let allocations = DaySlotAllocator.allocate(
            requests: [
                DaySlotAllocator.Request(id: "low", estimatedMinutes: 30, priority: .low),
                DaySlotAllocator.Request(id: "high", estimatedMinutes: 30, priority: .high)
            ],
            existingTasks: [],
            workHours: workHours,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(allocations.count, 2)
        let high = allocations.first { $0.id == "high" }!.scheduledTime
        let low = allocations.first { $0.id == "low" }!.scheduledTime
        XCTAssertLessThan(high, low)
    }

    func testPreferredStartUsedWhenNoConflict() {
        let now = makeDate(year: 2026, month: 8, day: 4, hour: 10)
        let preferred = makeDate(year: 2026, month: 8, day: 4, hour: 14)
        let allocations = DaySlotAllocator.allocate(
            requests: [
                DaySlotAllocator.Request(
                    id: "focus",
                    estimatedMinutes: 45,
                    priority: .medium,
                    preferredStart: preferred
                )
            ],
            existingTasks: [],
            workHours: workHours,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(
            calendar.component(.hour, from: allocations[0].scheduledTime),
            14
        )
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
