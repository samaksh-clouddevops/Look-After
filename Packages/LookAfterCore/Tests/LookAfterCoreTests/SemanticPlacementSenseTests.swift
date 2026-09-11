import XCTest
@testable import LookAfterCore

final class SemanticPlacementSenseTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    func testUntitledDinnerIsAMealNotGeneric() {
        let dinner = LifeTask(title: "Dinner", estimatedMinutes: 45)
        let profile = TaskSemanticProfileBuilder.build(from: dinner)
        XCTAssertEqual(profile.subtype, "meal")
        XCTAssertEqual(profile.preferredTimeWindows, [.evening])
    }

    func testDentistIsBusinessHoursAppointment() {
        let task = LifeTask(title: "Dentist appointment", estimatedMinutes: 45)
        let profile = TaskSemanticProfileBuilder.build(from: task)
        XCTAssertEqual(profile.subtype, "Appointment")
        XCTAssertTrue(profile.schedulingConstraints.contains(.requiresStoreOpen))
    }

    func testStudyIsLearningNotGeneric() {
        let task = LifeTask(title: "Study chapter 4", lifeArea: .learning, estimatedMinutes: 40)
        let profile = TaskSemanticProfileBuilder.build(from: task)
        XCTAssertEqual(profile.semanticType, .learning)
        XCTAssertTrue(profile.forbiddenTimeWindows.contains(.night))
    }

    func testGroceryAtNightDoesNotMakeSense() throws {
        let day = try day()
        let night = try date(hour: 22, on: day)
        let grocery = LifeTask(title: "Grocery shopping", estimatedMinutes: 40, scheduledDate: day)
        let verdict = SemanticPlacementSense.judge(
            SemanticPlacementSense.Input(
                task: grocery,
                proposedStart: night,
                durationMinutes: 40,
                calendar: calendar
            )
        )
        if case .doesNotMakeSense = verdict {
            // expected
        } else {
            XCTFail("Grocery at 22:00 should not make sense, got \(verdict)")
        }
    }

    func testDeepWorkAtNightDoesNotMakeSense() throws {
        let day = try day()
        let night = try date(hour: 22, on: day)
        let work = LifeTask(title: "Implement OAuth sign-in flow", difficulty: .hard, estimatedMinutes: 60, scheduledDate: day)
        let verdict = SemanticPlacementSense.judge(
            SemanticPlacementSense.Input(
                task: work,
                proposedStart: night,
                durationMinutes: 60,
                calendar: calendar
            )
        )
        if case .doesNotMakeSense = verdict {
            // expected
        } else {
            XCTFail("Deep work at 22:00 should not make sense, got \(verdict)")
        }
    }

    func testGymImmediatelyAfterLunchDoesNotMakeSense() throws {
        let day = try day()
        let lunchStart = try date(hour: 12, on: day)
        let gymStart = try date(hour: 12, minute: 50, on: day)
        let lunch = LifeTask(
            id: "lunch",
            title: "Lunch",
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: lunchStart,
            scheduledEndTime: lunchStart.addingTimeInterval(45 * 60)
        )
        let gym = LifeTask(id: "gym", title: "Gym", estimatedMinutes: 60, scheduledDate: day)

        let verdict = SemanticPlacementSense.judge(
            SemanticPlacementSense.Input(
                task: gym,
                proposedStart: gymStart,
                durationMinutes: 60,
                neighborTasks: [lunch],
                calendar: calendar
            )
        )
        if case .doesNotMakeSense = verdict {
            // expected
        } else {
            XCTFail("Gym 20 minutes after lunch should not make sense, got \(verdict)")
        }
    }

    func testGymInPreferredEveningMakesSense() throws {
        let day = try day()
        let evening = try date(hour: 18, on: day)
        let gym = LifeTask(title: "Gym", estimatedMinutes: 60, scheduledDate: day)
        let verdict = SemanticPlacementSense.judge(
            SemanticPlacementSense.Input(
                task: gym,
                proposedStart: evening,
                durationMinutes: 60,
                calendar: calendar
            )
        )
        XCTAssertEqual(verdict, .makesSense)
    }

    func testAfternoonGymNeedsAIRatherThanHardNo() throws {
        let day = try day()
        let afternoon = try date(hour: 15, on: day)
        let gym = LifeTask(title: "Gym", estimatedMinutes: 60, scheduledDate: day)
        let verdict = SemanticPlacementSense.judge(
            SemanticPlacementSense.Input(
                task: gym,
                proposedStart: afternoon,
                durationMinutes: 60,
                calendar: calendar
            )
        )
        if case .needsAI = verdict {
            // expected — semantics are unsure, AI should judge
        } else {
            XCTFail("Afternoon gym should need AI, got \(verdict)")
        }
    }

    func testGenericTaskAtNightNeedsAI() throws {
        let day = try day()
        let night = try date(hour: 21, minute: 15, on: day)
        let pack = LifeTask(title: "Pack the bag", estimatedMinutes: 50, scheduledDate: day)
        let dayEnd = try date(hour: 23, minute: 30, on: day)
        let verdict = SemanticPlacementSense.judge(
            SemanticPlacementSense.Input(
                task: pack,
                proposedStart: night,
                durationMinutes: 50,
                calendar: calendar,
                dayEnd: dayEnd
            )
        )
        if case .needsAI = verdict {
            // expected
        } else {
            XCTFail("Unknown long night task should need AI, got \(verdict)")
        }
    }

    func testMedicationInEveningIsRejectedByGuard() throws {
        let day = try day()
        let evening = try date(hour: 20, on: day)
        let meds = LifeTask(title: "Take Levothyroxine", estimatedMinutes: 2, scheduledDate: day)
        let result = SchedulePlacementGuard.evaluate(
            proposedStart: evening,
            durationMinutes: 2,
            task: meds,
            occupied: [],
            calendar: calendar,
            mode: .rejectOutsideBox
        )
        if case .rejected = result {
            // expected
        } else {
            XCTFail("Morning thyroid meds at 20:00 should be rejected, got \(result)")
        }
    }

    func testAllocatorDoesNotPlantGroceryAtNight() throws {
        let now = try date(hour: 10, on: day())
        let grocery = LifeTask(title: "Grocery shopping", estimatedMinutes: 40)
        let allocations = DaySlotAllocator.allocate(
            requests: [DaySlotAllocator.Request.makingSense(of: grocery, on: now, calendar: calendar)],
            existingTasks: [],
            workHours: PlanningSchedulePolicy.WorkHours(startHour: 9, endHour: 23),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(allocations.count, 1)
        let hour = calendar.component(.hour, from: allocations[0].scheduledTime)
        XCTAssertGreaterThanOrEqual(hour, 11)
        XCTAssertLessThan(hour, 17)
    }

    func testAllocatorSkipsAfternoonForGymWhenEveningIsOpen() throws {
        let now = try date(hour: 14, on: day())
        let gym = LifeTask(title: "Gym", estimatedMinutes: 60)
        let allocations = DaySlotAllocator.allocate(
            requests: [DaySlotAllocator.Request.makingSense(of: gym, on: now, calendar: calendar)],
            existingTasks: [],
            workHours: PlanningSchedulePolicy.WorkHours(startHour: 9, endHour: 21),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(allocations.count, 1)
        let hour = calendar.component(.hour, from: allocations[0].scheduledTime)
        XCTAssertGreaterThanOrEqual(hour, 17)
    }

    func testAllocatorKeepsGymAfterMealBuffer() throws {
        let now = try date(hour: 17, on: day())
        let lunchStart = try date(hour: 17, on: day())
        let lunch = LifeTask(
            id: "dinner",
            title: "Dinner",
            estimatedMinutes: 45,
            scheduledDate: calendar.startOfDay(for: now),
            scheduledTime: lunchStart,
            schedulingMode: .fixedTime,
            scheduledEndTime: lunchStart.addingTimeInterval(45 * 60)
        )
        let gym = LifeTask(title: "Gym", estimatedMinutes: 60)
        let allocations = DaySlotAllocator.allocate(
            requests: [DaySlotAllocator.Request.makingSense(of: gym, on: now, calendar: calendar)],
            existingTasks: [lunch],
            workHours: PlanningSchedulePolicy.WorkHours(startHour: 9, endHour: 21),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(allocations.count, 1)
        let start = allocations[0].scheduledTime
        XCTAssertGreaterThanOrEqual(start.timeIntervalSince(lunch.scheduledEndTime!), 45 * 60 - 1)
    }

    private func day() throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 9)))
    }

    private func date(hour: Int, minute: Int = 0, on day: Date) throws -> Date {
        try XCTUnwrap(calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day))
    }
}
