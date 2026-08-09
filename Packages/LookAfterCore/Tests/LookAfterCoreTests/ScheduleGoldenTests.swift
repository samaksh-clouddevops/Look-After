import XCTest
@testable import LookAfterCore

/// Golden integration scenarios for schedule substrate — timeline order, anchors, idempotency.
final class ScheduleGoldenTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    /// Monday 2026-08-03 at 11:44 AM — the screenshot class of bugs (Dinner at noon, Commute after Office).
    func testMondayMorningAnchorOrderAndMealTiming() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 3)))
        let now = try XCTUnwrap(calendar.date(bySettingHour: 11, minute: 44, second: 0, of: day))

        var profile = UserLifeProfile()
        profile.workStartHour = 9
        profile.workEndHour = 17
        profile.fixedScheduleNotes = "Daily Stand-up 2:35 PM"

        var dinner = LifeTask(
            title: "Dinner",
            lifeArea: .health,
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day),
            tags: ["daily-routine", "fixed"],
            schedulingMode: .flexible,
            userId: "user-1"
        )
        dinner = TaskEphemeralityDefaults.enrich(dinner)

        let commute = LifeTask(
            title: "Commute & Reset",
            lifeArea: .personal,
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: calendar.date(bySettingHour: 10, minute: 30, second: 0, of: day),
            tags: ["daily-routine"],
            userId: "user-1"
        )
        let office = LifeTask(
            title: "Office Work",
            lifeArea: .work,
            estimatedMinutes: 480,
            scheduledDate: day,
            scheduledTime: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day),
            tags: ["daily-routine", "fixed"],
            schedulingMode: .fixedTime,
            userId: "user-1"
        )
        let standup = LifeTask(
            title: "Daily Stand-up",
            lifeArea: .work,
            estimatedMinutes: 30,
            scheduledDate: day,
            userId: "user-1"
        )

        // Drift correction — Dinner should snap to evening anchor, not stay at noon.
        let dinnerAnchor = try XCTUnwrap(
            RoutineScheduleAnchorResolver.resolve(for: dinner, on: day, profile: profile, calendar: calendar)
        )
        XCTAssertEqual(calendar.component(.hour, from: dinnerAnchor.start), 19)
        XCTAssertTrue(RoutineScheduleAnchorResolver.shouldRestore(task: dinner, anchor: dinnerAnchor, calendar: calendar))

        // Commute must precede office work.
        let commuteStart = try XCTUnwrap(
            RoutineScheduleAnchorResolver.preferredStart(for: commute, on: day, profile: profile, calendar: calendar)
        )
        let officeStart = try XCTUnwrap(
            RoutineScheduleAnchorResolver.preferredStart(for: office, on: day, profile: profile, calendar: calendar)
        )
        XCTAssertLessThan(commuteStart, officeStart)

        // Stand-up from fixed note lands at 2:35 PM.
        let standupAnchor = try XCTUnwrap(
            RoutineScheduleAnchorResolver.resolve(for: standup, on: day, profile: profile, calendar: calendar)
        )
        XCTAssertEqual(calendar.component(.hour, from: standupAnchor.start), 14)
        XCTAssertEqual(calendar.component(.minute, from: standupAnchor.start), 35)

        // Timeline projection uses typed scheduleKind — flexible vs fixed.
        var correctedDinner = dinner
        correctedDinner.scheduledTime = dinnerAnchor.start
        correctedDinner.scheduledEndTime = dinnerAnchor.end
        correctedDinner.applyTimeConstraint(.anchored)

        let events = LifeTimelinePresenter.build(
            tasks: [correctedDinner, commute, office, standup],
            completedToday: [],
            bills: [],
            shoppingItems: [],
            contacts: [],
            now: now,
            referenceDay: day,
            calendar: calendar
        )
        let dinnerEvent = try XCTUnwrap(events.first { $0.title == "Dinner" })
        XCTAssertEqual(dinnerEvent.scheduleKind, .fixedWindow)
        XCTAssertFalse(dinnerEvent.scheduleKind.isFlexibleToday)
        XCTAssertEqual(calendar.component(.hour, from: dinnerEvent.date), 19)

        // Unified planner (when enabled) produces same-day slots without overlapping anchored blocks.
        let plan = DaySchedulePlanner.plan(
            tasks: [correctedDinner, commute, office, standup],
            on: day,
            profile: profile,
            now: now,
            calendar: calendar
        )
        XCTAssertFalse(plan.slots.isEmpty)
        let dinnerSlot = try XCTUnwrap(plan.slots.first { $0.taskID == dinner.id })
        XCTAssertEqual(calendar.component(.hour, from: dinnerSlot.start), 19)
    }

    func testDoubleReconcilePlanIsStable() throws {
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 7)))
        let nine = try XCTUnwrap(calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day))
        let eleven = try XCTUnwrap(calendar.date(bySettingHour: 11, minute: 0, second: 0, of: day))

        let tasks = [
            LifeTask(
                title: "Deep work",
                estimatedMinutes: 60,
                scheduledDate: day,
                scheduledTime: nine,
                userId: "user-1"
            ),
            LifeTask(
                title: "Email",
                estimatedMinutes: 30,
                scheduledDate: day,
                scheduledTime: eleven,
                userId: "user-1"
            ),
        ]

        let first = DaySchedulePlanner.plan(tasks: tasks, on: day, calendar: calendar)
        let second = DaySchedulePlanner.plan(tasks: tasks, on: day, calendar: calendar)
        XCTAssertEqual(first.slots.map(\.taskID), second.slots.map(\.taskID))
        XCTAssertEqual(
            first.slots.map { $0.start.timeIntervalSince1970 },
            second.slots.map { $0.start.timeIntervalSince1970 }
        )
    }

    func testScheduleKindTypedFlexibleSemantics() {
        XCTAssertTrue(TimelineScheduleKind.flexibleDay.isFlexibleToday)
        XCTAssertTrue(TimelineScheduleKind.floating.isFlexibleToday)
        XCTAssertFalse(TimelineScheduleKind.fixedWindow.isFlexibleToday)
    }
}
