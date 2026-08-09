import XCTest
import LookAfterCore
@testable import LookAfterFeatures

@MainActor
final class TimelineConstraintViewModelTests: XCTestCase {

    private var spy: InteractionTelemetrySpy!
    private var vm: TimelineConstraintViewModel!
    private var updated: [LifeTask] = []

    override func setUp() {
        super.setUp()
        spy = InteractionTelemetrySpy()
        updated = []
        vm = TimelineConstraintViewModel(telemetry: spy) { [weak self] task in
            self?.updated.append(task)
        }
        let tasks = [
            LifeTask(id: "a", title: "Anchored meeting", schedulingMode: .fixedTime, timeConstraint: .anchored, userId: "u"),
            LifeTask(id: "b", title: "Flexible deep work", schedulingMode: .flexible, timeConstraint: .flexible, userId: "u"),
            LifeTask(id: "c", title: "Fluid errand", schedulingMode: .flexible, timeConstraint: .fluid, userId: "u"),
        ]
        vm.seed(tasks: tasks)
    }

    func testHardenIntentMovesTowardAnchored() {
        vm.handle(.hardenConstraint(taskID: "c"))
        XCTAssertEqual(vm.constraint(for: "c"), .flexible)
        vm.handle(.hardenConstraint(taskID: "c"))
        XCTAssertEqual(vm.constraint(for: "c"), .anchored)
        // Already hard
        vm.handle(.hardenConstraint(taskID: "c"))
        XCTAssertEqual(vm.constraint(for: "c"), .anchored)
        XCTAssertEqual(spy.events.count, 2)
        XCTAssertEqual(spy.events.last?.to, .anchored)
        XCTAssertEqual(spy.events.last?.source, .swipe)
        XCTAssertFalse(updated.isEmpty)
        XCTAssertEqual(updated.last?.timeConstraint, .anchored)
        XCTAssertEqual(updated.last?.schedulingMode, .fixedTime)
    }

    func testSoftenIntentMovesTowardFluid() {
        vm.handle(.softenConstraint(taskID: "a"))
        XCTAssertEqual(vm.constraint(for: "a"), .flexible)
        vm.handle(.softenConstraint(taskID: "a"))
        XCTAssertEqual(vm.constraint(for: "a"), .fluid)
        XCTAssertEqual(spy.events.map(\.to), [.flexible, .fluid])
        XCTAssertEqual(spy.events.first?.from, .anchored)
    }

    func testAccessibilitySetConstraintLogsSystemSource() {
        vm.handle(.setConstraint(taskID: "b", .anchored))
        XCTAssertEqual(vm.constraint(for: "b"), .anchored)
        XCTAssertEqual(spy.events.last?.source, .accessibility)
        XCTAssertEqual(spy.events.last?.from, .flexible)
        XCTAssertEqual(spy.events.last?.to, .anchored)
    }

    func testNoTelemetryWhenConstraintUnchanged() {
        vm.handle(.hardenConstraint(taskID: "a"))
        XCTAssertTrue(spy.events.isEmpty)
    }

    func testVerticalDragSessionFlags() {
        XCTAssertNil(vm.activeDragTaskID)
        vm.handle(.beginVerticalDrag(taskID: "b"))
        XCTAssertEqual(vm.activeDragTaskID, "b")
        vm.handle(.endVerticalDrag)
        XCTAssertNil(vm.activeDragTaskID)
    }

    func testCommitOffsetSkippedForAnchored() {
        let before = Date(timeIntervalSince1970: 1_700_000_000)
        var task = LifeTask(
            id: "a",
            title: "Lock",
            scheduledTime: before,
            schedulingMode: .fixedTime,
            timeConstraint: .anchored,
            userId: "u"
        )
        vm.upsert(task: task)
        updated.removeAll()
        vm.handle(.commitVerticalOffset(taskID: "a", offsetMinutes: 30))
        XCTAssertTrue(updated.isEmpty)
    }

    func testCommitOffsetMovesFlexibleSchedule() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var task = LifeTask(
            id: "b",
            title: "Move me",
            scheduledTime: start,
            schedulingMode: .flexible,
            timeConstraint: .flexible,
            userId: "u"
        )
        vm.upsert(task: task)
        updated.removeAll()
        vm.handle(.commitVerticalOffset(taskID: "b", offsetMinutes: 15))
        XCTAssertEqual(updated.count, 1)
        let delta = updated[0].scheduledTime!.timeIntervalSince(start)
        XCTAssertEqual(delta, 15 * 60, accuracy: 0.5)
    }

    func testCommitAbsoluteDragSetsUserPlacedStart() {
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        let target = calendar.date(bySettingHour: 10, minute: 30, second: 0, of: Date())!
        var task = LifeTask(
            id: "b",
            title: "Move me",
            scheduledDate: calendar.startOfDay(for: start),
            scheduledTime: start,
            schedulingMode: .flexible,
            timeConstraint: .flexible,
            userId: "u"
        )
        vm.upsert(task: task)
        updated.removeAll()
        vm.handle(.commitVerticalDrag(taskID: "b", proposedStart: target))
        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated[0].scheduledTime, target)
        XCTAssertNotNil(updated[0].userPlacedScheduleAt)
    }

    func testBeginVerticalDragExposesDurationForMeter() {
        var task = LifeTask(
            id: "b",
            title: "Move me",
            estimatedMinutes: 45,
            schedulingMode: .flexible,
            timeConstraint: .flexible,
            userId: "u"
        )
        vm.upsert(task: task)
        vm.handle(.beginVerticalDrag(taskID: "b"))
        XCTAssertEqual(vm.proposedDragDurationMinutes, 45)
        vm.handle(.endVerticalDrag)
        XCTAssertNil(vm.proposedDragDurationMinutes)
    }

    func testScheduleDragCommittedCallbackFires() {
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        let target = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
        var task = LifeTask(
            id: "b",
            title: "Move me",
            scheduledDate: calendar.startOfDay(for: start),
            scheduledTime: start,
            schedulingMode: .flexible,
            timeConstraint: .flexible,
            userId: "u"
        )
        vm.upsert(task: task)
        var commitCount = 0
        vm.onScheduleDragCommitted = { commitCount += 1 }
        vm.handle(.commitVerticalDrag(taskID: "b", proposedStart: target))
        XCTAssertEqual(commitCount, 1)
    }

    func testCommitAbsoluteDragForUnslottedTask() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let target = calendar.date(bySettingHour: 15, minute: 30, second: 0, of: Date())!
        var task = LifeTask(
            id: "unslotted",
            title: "Vocal Practice",
            estimatedMinutes: 45,
            scheduledDate: day,
            schedulingMode: .flexible,
            timeConstraint: .flexible,
            userId: "u"
        )
        vm.upsert(task: task)
        updated.removeAll()
        vm.handle(.commitVerticalDrag(taskID: "unslotted", proposedStart: target))
        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated[0].scheduledTime, target)
        XCTAssertNotNil(updated[0].scheduledEndTime)
        XCTAssertNotNil(updated[0].userPlacedScheduleAt)
    }
}
