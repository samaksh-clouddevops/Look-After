import XCTest
@testable import LookAfterCore

final class SimulationEngineTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()
    private let day = Date(timeIntervalSince1970: 1_720_000_000)

    func testSimulateDoesNotMutateBaseline() {
        let baselineTask = task(id: "a", title: "Standup", hour: 10, minutes: 60, constraint: .anchored)
        let baseline = LifeState(activeTasks: [baselineTask], consecutiveHighLoadDays: 1)
        let hypo = task(id: "h", title: "What-if deep work", hour: 10, minutes: 90, constraint: .fluid)

        let result = SimulationEngine.simulate(
            baselineState: baseline,
            hypotheticalTask: hypo,
            day: day,
            calendar: calendar
        )

        XCTAssertEqual(baseline.activeTasks.count, 1)
        XCTAssertEqual(baseline.activeTasks.first?.id, "a")
        XCTAssertEqual(baseline.activeTasks.first?.scheduledTime, baselineTask.scheduledTime)
        XCTAssertTrue(result.impact.hypotheticalTaskIDs.contains("h"))
        XCTAssertTrue(result.simulatedState.activeTasks.contains(where: { $0.id == "h" }))
    }

    func testDryRunLeavesSharedParkedQueueUntouched() {
        let park = ParkedTaskQueueStore.shared
        let before = park.snapshot().entries.count

        // Dense anchored day — fluid hypo is forced to park/defer.
        let blocks = (9..<18).map { h in
            task(id: "fix-\(h)", title: "Meeting \(h)", hour: h, minutes: 55, constraint: .anchored)
        }
        let baseline = LifeState(activeTasks: blocks, consecutiveHighLoadDays: 0)
        let hypo = task(id: "errand", title: "Errand", hour: 10, minutes: 60, constraint: .fluid)

        _ = SimulationEngine.simulate(
            baselineState: baseline,
            hypotheticalTask: hypo,
            day: day,
            calendar: calendar
        )

        XCTAssertEqual(park.snapshot().entries.count, before)
    }

    func testSmoothAbsorbWhenDayIsOpen() {
        let light = task(id: "a", title: "Email", hour: 9, minutes: 30, constraint: .flexible)
        let baseline = LifeState(activeTasks: [light], consecutiveHighLoadDays: 0)
        let hypo = task(id: "b", title: "Walk", hour: 14, minutes: 30, constraint: .fluid)

        let result = SimulationEngine.simulate(
            baselineState: baseline,
            hypotheticalTask: hypo,
            day: day,
            calendar: calendar
        )

        XCTAssertEqual(result.impact.parkedTaskDelta, 0)
        XCTAssertEqual(result.impact.supersededTasksDelta, 0)
        XCTAssertTrue(result.impact.absorbsSmoothly || result.impact.severity == .success || result.impact.severity == .neutral)
    }

    func testReconcileStateConvenience() {
        let a = task(id: "a", title: "A", hour: 11, minutes: 60, constraint: .anchored)
        let b = task(id: "b", title: "B", hour: 11, minutes: 45, constraint: .flexible)
        let state = LifeState(activeTasks: [a, b])
        let result = DayScheduleReconciler.reconcile(
            state: state,
            on: day,
            calendar: calendar,
            options: .dryRun
        )
        XCTAssertTrue(result.conflictTaskIDs.isEmpty)
        XCTAssertFalse(DayScheduleReconciler.hasOverlap(result.tasks, on: day, calendar: calendar))
    }

    func testCommitIntentCarriesHypotheticalTasks() {
        let baseline = LifeState(activeTasks: [], consecutiveHighLoadDays: 0)
        let hypo = task(id: "h1", title: "Draft blog", hour: 15, minutes: 45, constraint: .fluid)
        let sim = SimulationEngine.simulate(
            baselineState: baseline,
            hypotheticalTask: hypo,
            day: day,
            calendar: calendar
        )
        let intent = LifeEngine.shared.commitSimulationIntent(from: sim)
        XCTAssertEqual(intent.tasksToIngest.map(\.id), ["h1"])
        XCTAssertEqual(intent.impact.hypotheticalTaskIDs, sim.impact.hypotheticalTaskIDs)
    }

    // MARK: - Helpers

    private func task(
        id: String,
        title: String,
        hour: Int,
        minutes: Int,
        constraint: TimeConstraint,
        priority: Priority = .medium
    ) -> LifeTask {
        let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        let end = start.addingTimeInterval(TimeInterval(minutes * 60))
        return LifeTask(
            id: id,
            title: title,
            priority: priority,
            status: .pending,
            estimatedMinutes: minutes,
            scheduledDate: calendar.startOfDay(for: day),
            scheduledTime: start,
            schedulingMode: constraint.asSchedulingMode,
            timeConstraint: constraint,
            scheduledEndTime: end,
            userId: "u"
        )
    }
}
