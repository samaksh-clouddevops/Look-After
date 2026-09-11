import XCTest
import LookAfterCore
@testable import LookAfterFeatures

final class TimelineConstraintViewModelTests: XCTestCase {

    @MainActor private var spy: InteractionTelemetrySpy!
    @MainActor private var vm: TimelineConstraintViewModel!
    @MainActor private var updated: [LifeTask] = []

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        await configureFixture()
    }

    @MainActor
    private func configureFixture() {
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

    @MainActor
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

    @MainActor
    func testSoftenIntentMovesTowardFluid() {
        vm.handle(.softenConstraint(taskID: "a"))
        XCTAssertEqual(vm.constraint(for: "a"), .flexible)
        vm.handle(.softenConstraint(taskID: "a"))
        XCTAssertEqual(vm.constraint(for: "a"), .fluid)
        XCTAssertEqual(spy.events.map(\.to), [.flexible, .fluid])
        XCTAssertEqual(spy.events.first?.from, .anchored)
    }

    @MainActor
    func testAccessibilitySetConstraintLogsSystemSource() {
        vm.handle(.setConstraint(taskID: "b", .anchored))
        XCTAssertEqual(vm.constraint(for: "b"), .anchored)
        XCTAssertEqual(spy.events.last?.source, .accessibility)
        XCTAssertEqual(spy.events.last?.from, .flexible)
        XCTAssertEqual(spy.events.last?.to, .anchored)
    }

    @MainActor
    func testNoTelemetryWhenConstraintUnchanged() {
        vm.handle(.hardenConstraint(taskID: "a"))
        XCTAssertTrue(spy.events.isEmpty)
    }

    @MainActor
    func testVerticalDragSessionFlags() {
        XCTAssertNil(vm.activeDragTaskID)
        vm.handle(.beginVerticalDrag(taskID: "b"))
        XCTAssertEqual(vm.activeDragTaskID, "b")
        vm.handle(.endVerticalDrag)
        XCTAssertNil(vm.activeDragTaskID)
    }

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
    func testDinnerDragToMorningIsRejected() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let evening = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: Date())!
        let morning = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
        var dinner = LifeTask(
            id: "dinner",
            title: "Dinner",
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: evening,
            schedulingMode: .flexible,
            timeConstraint: .flexible,
            userId: "u"
        )
        vm.upsert(task: dinner)
        updated.removeAll()
        vm.handle(.commitVerticalDrag(taskID: "dinner", proposedStart: morning))
        XCTAssertTrue(updated.isEmpty)
    }

    @MainActor
    func testGroceryDragToNightIsRejected() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let afternoon = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!
        let night = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: Date())!
        var grocery = LifeTask(
            id: "grocery",
            title: "Grocery shopping",
            estimatedMinutes: 40,
            scheduledDate: day,
            scheduledTime: afternoon,
            schedulingMode: .flexible,
            timeConstraint: .flexible,
            userId: "u"
        )
        vm.upsert(task: grocery)
        updated.removeAll()
        vm.handle(.commitVerticalDrag(taskID: "grocery", proposedStart: night))
        XCTAssertTrue(updated.isEmpty)
    }

    @MainActor
    func testGymDragRightAfterLunchIsRejected() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let lunchStart = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let gymStart = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: Date())!
        let tooSoon = calendar.date(bySettingHour: 12, minute: 40, second: 0, of: Date())!
        var lunch = LifeTask(
            id: "lunch",
            title: "Lunch",
            estimatedMinutes: 45,
            scheduledDate: day,
            scheduledTime: lunchStart,
            schedulingMode: .fixedTime,
            timeConstraint: .anchored,
            userId: "u"
        )
        lunch.scheduledEndTime = lunchStart.addingTimeInterval(45 * 60)
        var gym = LifeTask(
            id: "gym",
            title: "Gym",
            estimatedMinutes: 60,
            scheduledDate: day,
            scheduledTime: gymStart,
            schedulingMode: .flexible,
            timeConstraint: .flexible,
            userId: "u"
        )
        vm.seed(tasks: [lunch, gym])
        updated.removeAll()
        vm.handle(.commitVerticalDrag(taskID: "gym", proposedStart: tooSoon))
        XCTAssertTrue(updated.isEmpty)
    }

    @MainActor
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

    @MainActor
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

    @MainActor
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
