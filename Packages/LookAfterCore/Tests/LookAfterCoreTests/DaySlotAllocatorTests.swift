import XCTest
@testable import LookAfterCore

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

    func testDoesNotScheduleOverProtectedGymWindow() {
        let now = makeDate(year: 2026, month: 8, day: 4, hour: 10)
        let gym = ProtectedTimeBlock(
            label: "Gym",
            days: .weekdays,
            startHour: 18,
            startMinute: 0,
            endHour: 19,
            endMinute: 0,
            protection: .neverSchedule
        )
        let windows = SchedulingWindows(
            officeHours: PlanningSchedulePolicy.WorkHours(startHour: 9, endHour: 22),
            protectedBlocks: [gym],
            creativeWindows: []
        )
        let preferred = makeDate(year: 2026, month: 8, day: 4, hour: 18)
        let allocations = DaySlotAllocator.allocateAcrossWindows(
            requests: [
                DaySlotAllocator.Request(
                    id: "deep-work",
                    estimatedMinutes: 60,
                    priority: .high,
                    preferredStart: preferred
                )
            ],
            existingTasks: [],
            windows: windows,
            on: makeDate(year: 2026, month: 8, day: 4),
            now: now,
            calendar: calendar
        )

        // Preferred 18:00 is gym — may place after gym, never before preferred / at wall-clock now.
        if allocations.isEmpty {
            return
        }
        XCTAssertEqual(allocations.count, 1)
        let start = allocations[0].scheduledTime
        let hour = calendar.component(.hour, from: start)
        XCTAssertGreaterThanOrEqual(start, preferred)
        XCTAssertNotEqual(hour, 18)
        XCTAssertGreaterThanOrEqual(hour, 19)
    }

    func testDinnerAllocatedInsideEveningFenceNotOfficeMorning() {
        let now = makeDate(year: 2026, month: 8, day: 4, hour: 10)
        let day = makeDate(year: 2026, month: 8, day: 4)
        let gymStart = makeDate(year: 2026, month: 8, day: 4, hour: 18)
        let gym = LifeTask(
            title: "Gym",
            estimatedMinutes: 90,
            scheduledDate: day,
            scheduledTime: gymStart,
            schedulingMode: .fixedTime,
            scheduledEndTime: makeDate(year: 2026, month: 8, day: 4, hour: 19, minute: 30)
        )
        let dinnerPreferred = makeDate(year: 2026, month: 8, day: 4, hour: 19)
        let allocations = DaySlotAllocator.allocate(
            requests: [
                DaySlotAllocator.Request(
                    id: "dinner",
                    estimatedMinutes: 45,
                    preferredStart: dinnerPreferred,
                    hourBounds: SchedulePlacementGuard.workHours(
                        forBox: TemporalBoundingBox(earliestStartHour: 17, latestStartHour: 21)
                    )
                )
            ],
            existingTasks: [gym],
            workHours: workHours,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(allocations.count, 1)
        let hour = calendar.component(.hour, from: allocations[0].scheduledTime)
        XCTAssertGreaterThanOrEqual(hour, 17)
        XCTAssertLessThanOrEqual(hour, 21)
        XCTAssertNotEqual(hour, 10)
    }

    /// Root bug: when preferred is still ahead, do not park the task at wall-clock `now`.
    func testUpcomingPreferredDoesNotFallBackToNow() {
        let now = makeDate(year: 2026, month: 8, day: 4, hour: 10)
        let preferred = makeDate(year: 2026, month: 8, day: 4, hour: 19)
        let day = makeDate(year: 2026, month: 8, day: 4)
        // Occupy the entire preferred search window so preferred + later-from-preferred both fail.
        let blocker = LifeTask(
            title: "Block evening",
            estimatedMinutes: 240,
            scheduledDate: day,
            scheduledTime: makeDate(year: 2026, month: 8, day: 4, hour: 17),
            schedulingMode: .fixedTime,
            scheduledEndTime: makeDate(year: 2026, month: 8, day: 4, hour: 22)
        )
        let allocations = DaySlotAllocator.allocate(
            requests: [
                DaySlotAllocator.Request(
                    id: "dinner",
                    estimatedMinutes: 45,
                    preferredStart: preferred,
                    hourBounds: SchedulePlacementGuard.workHours(
                        forBox: TemporalBoundingBox(earliestStartHour: 17, latestStartHour: 21)
                    )
                )
            ],
            existingTasks: [blocker],
            workHours: workHours,
            now: now,
            calendar: calendar
        )
        XCTAssertTrue(
            allocations.isEmpty,
            "Must leave unscheduled rather than inventing a 10 AM slot before an evening preferred"
        )
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
