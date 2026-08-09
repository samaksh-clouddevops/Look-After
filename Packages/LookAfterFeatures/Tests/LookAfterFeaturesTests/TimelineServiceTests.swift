import XCTest
@testable import LookAfterFeatures
import LookAfterCore

@MainActor
final class TimelineServiceTests: XCTestCase {
    func testRebuildProjectsSlottedFlexibleTaskRow() {
        let service = TimelineService()
        let today = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: today)!
        let task = LifeTask(
            title: "Flexible work",
            scheduledDate: today,
            scheduledTime: start,
            schedulingMode: .flexible,
            userId: "user-1"
        )

        service.rebuild(
            tasks: [task],
            completedToday: [],
            recurrenceTemplates: [],
            bills: [],
            shoppingItems: [],
            contacts: [],
            medications: []
        )

        XCTAssertFalse(service.snapshot.today.isEmpty)
        XCTAssertNotEqual(service.todayRows.first?.timeLabel, "Flexible")
    }

    func testUnslottedFlexibleTaskShowsGapAnchorTime() {
        let service = TimelineService()
        let today = Calendar.current.startOfDay(for: Date())
        let task = LifeTask(
            title: "Flexible work",
            scheduledDate: today,
            schedulingMode: .flexible,
            userId: "user-1"
        )

        service.rebuild(
            tasks: [task],
            completedToday: [],
            recurrenceTemplates: [],
            bills: [],
            shoppingItems: [],
            contacts: [],
            medications: []
        )

        let row = service.todayRows.first(where: { $0.title == "Flexible work" })
        XCTAssertNotNil(row)
        XCTAssertTrue(row?.isUnslottedFlexible ?? false, "Expected unslotted flexible row")
        XCTAssertNotEqual(row?.timeLabel, "Flexible")
        XCTAssertFalse(row?.timeLabel.isEmpty ?? true)
        XCTAssertFalse(row?.endTimeLabel.isEmpty ?? true)
        XCTAssertFalse(row?.isSuggestedSlot ?? true)
    }

    func testOptimisticCompletePatchMarksRowDone() {
        let service = TimelineService()
        let today = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: today)!
        let task = LifeTask(
            id: "abc",
            title: "Complete me",
            scheduledDate: today,
            scheduledTime: start,
            userId: "user-1"
        )

        service.rebuild(
            tasks: [task],
            completedToday: [],
            recurrenceTemplates: [],
            bills: [],
            shoppingItems: [],
            contacts: [],
            medications: []
        )

        service.applyPatch(.completed(taskId: "abc"))

        XCTAssertTrue(service.todayRows.first(where: { $0.taskId == "abc" })?.isCompleted == true)
    }

    func testFlexibleRowsUseFlexibleLabelNotMidnight() {
        let service = TimelineService()
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 10, minute: 0))!
        let day = Calendar.current.startOfDay(for: now)
        let start = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: day)!
        let task = LifeTask(
            title: "Anytime task",
            scheduledDate: day,
            scheduledTime: start,
            schedulingMode: .flexible,
            userId: "user-1"
        )

        service.rebuild(
            tasks: [task],
            completedToday: [],
            recurrenceTemplates: [],
            bills: [],
            shoppingItems: [],
            contacts: [],
            medications: [],
            now: now
        )

        let row = service.todayRows.first(where: { $0.title == "Anytime task" })
        XCTAssertNotNil(row)
        XCTAssertNotEqual(row?.timeLabel, "Flexible")
        XCTAssertFalse(row?.isPast ?? true)
        XCTAssertFalse(row?.scheduleRangeLabel.isEmpty ?? true)
    }

    func testAnchoredMidnightPlaceholderRowIsNotPast() {
        let service = TimelineService()
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 21, minute: 40))!
        let day = Calendar.current.startOfDay(for: now)
        var task = LifeTask(
            title: "Brush teeth — evening",
            scheduledDate: day,
            scheduledTime: day,
            tags: ["daily-routine"],
            schedulingMode: .fixedTime,
            userId: "user-1"
        )
        task = TaskConstraintAlignment.align(task)

        service.rebuild(
            tasks: [task],
            completedToday: [],
            recurrenceTemplates: [],
            bills: [],
            shoppingItems: [],
            contacts: [],
            medications: [],
            now: now
        )

        let row = service.todayRows.first(where: { $0.title.contains("Brush teeth") })
        XCTAssertNotNil(row)
        XCTAssertFalse(row?.timeLabel == "12:00 AM")
        XCTAssertFalse(row?.isPast ?? true)
        XCTAssertTrue(row?.isUnslottedFlexible ?? false)
    }

    func testCompletedWithoutSlotHidesMidnightTimeLabel() {
        let service = TimelineService()
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 22, minute: 0))!
        let day = Calendar.current.startOfDay(for: now)
        var completed = LifeTask(
            title: "Dinner",
            status: .completed,
            scheduledDate: day,
            userId: "user-1"
        )
        completed.updatedAt = Calendar.current.date(
            bySettingHour: 20, minute: 5, second: 0, of: day
        )!
        completed.completedAt = completed.updatedAt

        service.rebuild(
            tasks: [],
            completedToday: [completed],
            recurrenceTemplates: [],
            bills: [],
            shoppingItems: [],
            contacts: [],
            medications: [],
            now: now
        )

        let row = service.todayRows.first(where: { $0.title == "Dinner" })
        XCTAssertNotNil(row)
        XCTAssertNotEqual(row?.timeLabel, "12:00 AM")
        XCTAssertTrue(row?.isCompleted ?? false)
    }

    func testPendingUnslottedAtMidnightShowsEmptyTimeRail() {
        let service = TimelineService()
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 14, minute: 0))!
        let day = Calendar.current.startOfDay(for: now)
        let task = LifeTask(
            title: "Gym",
            scheduledDate: day,
            userId: "user-1"
        )

        service.rebuild(
            tasks: [task],
            completedToday: [],
            recurrenceTemplates: [],
            bills: [],
            shoppingItems: [],
            contacts: [],
            medications: [],
            now: now
        )

        let row = service.todayRows.first(where: { $0.title == "Gym" })
        XCTAssertNotNil(row)
        XCTAssertNotEqual(row?.timeLabel, "12:00 AM")
    }
}
