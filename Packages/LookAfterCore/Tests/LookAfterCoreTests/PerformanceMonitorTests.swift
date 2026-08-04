import XCTest
@testable import LookAfterCore

/// Verifies PerformanceMonitor instrumentation, sorter budgets, and scorecard helpers.
final class PerformanceMonitorTests: XCTestCase {

    private let monitorOverheadHardFailMs: Double = 5

    func testMeasureReturnsBlockValueAndStaysUnderOverheadBudget() {
        let start = CFAbsoluteTimeGetCurrent()
        let value = PerformanceMonitor.measure("unit-test-sync", warnAfterMs: 100) {
            42
        }
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

        XCTAssertEqual(value, 42)
        XCTAssertLessThan(
            elapsedMs,
            monitorOverheadHardFailMs,
            "PerformanceMonitor.measure overhead \(elapsedMs)ms exceeds \(monitorOverheadHardFailMs)ms"
        )
    }

    func testMeasureAsyncReturnsBlockValue() async throws {
        let value = try await PerformanceMonitor.measureAsync("unit-test-async", warnAfterMs: 100) {
            try await Task.sleep(nanoseconds: 1_000_000)
            return "ok"
        }
        XCTAssertEqual(value, "ok")
    }

    func testSortForToday_100Tasks_WithinFrameBudget() {
        let tasks = makeTasks(count: 100)
        let start = CFAbsoluteTimeGetCurrent()
        let sorted = TaskListSorter.sortForToday(tasks)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let score = PerformanceBudgets.score(
            durationMs: elapsedMs,
            targetMs: PerformanceBudgets.taskSort100TargetMs,
            hardFailMs: PerformanceBudgets.taskSort100HardFailMs
        )

        XCTAssertEqual(sorted.count, 100)
        XCTAssertTrue(
            PerformanceBudgets.isAcceptable(score),
            "100-task sort took \(elapsedMs)ms (score \(score)) — hard fail > \(PerformanceBudgets.taskSort100HardFailMs)ms"
        )
    }

    func testSortForToday_500Tasks_WithinBudget() {
        let tasks = makeTasks(count: 500)
        let start = CFAbsoluteTimeGetCurrent()
        let sorted = TaskListSorter.sortForToday(tasks)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let score = PerformanceBudgets.score(
            durationMs: elapsedMs,
            targetMs: PerformanceBudgets.taskSort500TargetMs,
            hardFailMs: PerformanceBudgets.taskSort500HardFailMs
        )

        XCTAssertEqual(sorted.count, 500)
        XCTAssertTrue(
            PerformanceBudgets.isAcceptable(score),
            "500-task sort took \(elapsedMs)ms (score \(score))"
        )
    }

    func testSortByPriorityThenSchedule_500Tasks_WithinBudget() {
        let tasks = makeTasks(count: 500)
        let start = CFAbsoluteTimeGetCurrent()
        let sorted = TaskListSorter.sortByPriorityThenSchedule(tasks)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

        XCTAssertEqual(sorted.count, 500)
        XCTAssertLessThan(elapsedMs, PerformanceBudgets.taskSort500HardFailMs, "Priority sort took \(elapsedMs)ms")
    }

    func testScorecard_AtTargetIs100() {
        let score = PerformanceBudgets.score(durationMs: 100, targetMs: 100, hardFailMs: 500)
        XCTAssertEqual(score, 100, accuracy: 0.01)
        XCTAssertTrue(PerformanceBudgets.isAcceptable(score))
    }

    func testScorecard_AtHardFailIsBelowAcceptable() {
        let score = PerformanceBudgets.score(durationMs: 500, targetMs: 100, hardFailMs: 500)
        XCTAssertLessThan(score, 70)
        XCTAssertFalse(PerformanceBudgets.isAcceptable(score))
    }

    func testScorecard_BetweenTargetAndHardFailIsAcceptable() {
        let score = PerformanceBudgets.score(durationMs: 300, targetMs: 100, hardFailMs: 500)
        XCTAssertGreaterThanOrEqual(score, 70)
        XCTAssertLessThan(score, 100)
        XCTAssertTrue(PerformanceBudgets.isAcceptable(score))
    }

    // MARK: - Fixtures

    private func makeTasks(count: Int) -> [LifeTask] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        return (0..<count).map { index in
            let hour = 8 + (index % 10)
            let time = calendar.date(bySettingHour: hour, minute: index % 60, second: 0, of: day)
            return LifeTask(
                title: "Task \(index)",
                lifeArea: LifeArea.allCases[index % LifeArea.allCases.count],
                priority: Priority(rawValue: index % 5) ?? .medium,
                status: .pending,
                estimatedMinutes: 15 + (index % 45),
                scheduledDate: day,
                scheduledTime: time,
                userId: "perf-user"
            )
        }
    }
}
