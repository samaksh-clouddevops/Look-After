import XCTest
@testable import LookAfterFeatures
import LookAfterCore

@MainActor
final class TimelineServiceTests: XCTestCase {
    func testRebuildProjectsFlexibleTaskRow() {
        let service = TimelineService()
        let today = Calendar.current.startOfDay(for: Date())
        let task = LifeTask(
            title: "Flexible work",
            scheduledDate: today,
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
        XCTAssertEqual(service.todayRows.first?.timeLabel, "Flexible")
        XCTAssertFalse(service.todayRows.first?.isPast ?? true)
    }

    func testOptimisticCompletePatchMarksRowDone() {
        let service = TimelineService()
        let today = Calendar.current.startOfDay(for: Date())
        let task = LifeTask(id: "abc", title: "Complete me", scheduledDate: today, userId: "user-1")

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
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 20, minute: 0))!
        let day = Calendar.current.startOfDay(for: now)
        let task = LifeTask(
            title: "Anytime task",
            scheduledDate: day,
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

        let row = service.todayRows.first
        XCTAssertEqual(row?.timeLabel, "Flexible")
        XCTAssertFalse(row?.isPast ?? true)
        XCTAssertTrue(row?.scheduleRangeLabel.isEmpty ?? false)
    }
}
