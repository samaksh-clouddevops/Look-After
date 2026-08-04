import XCTest
@testable import PerfBudgets

/// Runnable on Linux via Docker (Windows host) — verifies scorecard gates.
final class PerformanceBudgetsTests: XCTestCase {

    func testScore_AtOrUnderTarget_Is100() {
        XCTAssertEqual(PerformanceBudgets.score(durationMs: 0, targetMs: 100, hardFailMs: 500), 100)
        XCTAssertEqual(PerformanceBudgets.score(durationMs: 100, targetMs: 100, hardFailMs: 500), 100)
        XCTAssertTrue(PerformanceBudgets.isAcceptable(100))
    }

    func testScore_BetweenTargetAndHardFail_IsAcceptable() {
        let score = PerformanceBudgets.score(durationMs: 300, targetMs: 100, hardFailMs: 500)
        XCTAssertGreaterThanOrEqual(score, 70)
        XCTAssertLessThan(score, 100)
        XCTAssertTrue(PerformanceBudgets.isAcceptable(score))
    }

    func testScore_AtHardFail_IsNotAcceptable() {
        let score = PerformanceBudgets.score(durationMs: 500, targetMs: 100, hardFailMs: 500)
        XCTAssertLessThan(score, 70)
        XCTAssertFalse(PerformanceBudgets.isAcceptable(score))
    }

    func testScore_DoubleHardFail_IsZero() {
        let score = PerformanceBudgets.score(durationMs: 1000, targetMs: 100, hardFailMs: 500)
        XCTAssertEqual(score, 0, accuracy: 0.01)
    }

    func testScore_LinearMidpoint() {
        // Midway target→hardFail: 100 - 15 = 85
        let score = PerformanceBudgets.score(durationMs: 300, targetMs: 100, hardFailMs: 500)
        XCTAssertEqual(score, 85, accuracy: 0.5)
    }

    func testAllBudgetPairs_HaveHardFailAboveTarget() {
        let pairs: [(Double, Double)] = [
            (PerformanceBudgets.focusStateActivationTargetMs, PerformanceBudgets.focusStateActivationHardFailMs),
            (PerformanceBudgets.focusUIOpenTargetMs, PerformanceBudgets.focusUIOpenHardFailMs),
            (PerformanceBudgets.contextRefreshTargetMs, PerformanceBudgets.contextRefreshHardFailMs),
            (PerformanceBudgets.contextWarmRefreshTargetMs, PerformanceBudgets.contextWarmRefreshHardFailMs),
            (PerformanceBudgets.localSaveReturnTargetMs, PerformanceBudgets.localSaveReturnHardFailMs),
            (PerformanceBudgets.localWrite200TasksTargetMs, PerformanceBudgets.localWrite200TasksHardFailMs),
            (PerformanceBudgets.localLoad200TasksTargetMs, PerformanceBudgets.localLoad200TasksHardFailMs),
            (PerformanceBudgets.taskSort100TargetMs, PerformanceBudgets.taskSort100HardFailMs),
            (PerformanceBudgets.taskSort500TargetMs, PerformanceBudgets.taskSort500HardFailMs),
            (PerformanceBudgets.tabTransitionTargetMs, PerformanceBudgets.tabTransitionHardFailMs),
            (PerformanceBudgets.taskListOpenTargetMs, PerformanceBudgets.taskListOpenHardFailMs),
            (PerformanceBudgets.multiTabSweepTargetMs, PerformanceBudgets.multiTabSweepHardFailMs),
            (PerformanceBudgets.warmLaunchTargetMs, PerformanceBudgets.warmLaunchHardFailMs)
        ]
        for (target, hard) in pairs {
            XCTAssertGreaterThan(hard, target, "hardFail \(hard) must be > target \(target)")
            // Score at target must pass; score at hard fail must fail acceptable gate.
            XCTAssertTrue(PerformanceBudgets.isAcceptable(
                PerformanceBudgets.score(durationMs: target, targetMs: target, hardFailMs: hard)
            ))
            XCTAssertFalse(PerformanceBudgets.isAcceptable(
                PerformanceBudgets.score(durationMs: hard, targetMs: target, hardFailMs: hard)
            ))
        }
    }

    func testSimulatedScenarioMatrix_AllTargetsScore100() {
        let scenarios: [(String, Double, Double)] = [
            ("focus-vm", PerformanceBudgets.focusStateActivationTargetMs, PerformanceBudgets.focusStateActivationHardFailMs),
            ("focus-ui", PerformanceBudgets.focusUIOpenTargetMs, PerformanceBudgets.focusUIOpenHardFailMs),
            ("ctx-refresh", PerformanceBudgets.contextRefreshTargetMs, PerformanceBudgets.contextRefreshHardFailMs),
            ("save-return", PerformanceBudgets.localSaveReturnTargetMs, PerformanceBudgets.localSaveReturnHardFailMs),
            ("sort-100", PerformanceBudgets.taskSort100TargetMs, PerformanceBudgets.taskSort100HardFailMs),
            ("sort-500", PerformanceBudgets.taskSort500TargetMs, PerformanceBudgets.taskSort500HardFailMs),
            ("tab", PerformanceBudgets.tabTransitionTargetMs, PerformanceBudgets.tabTransitionHardFailMs),
            ("task-list", PerformanceBudgets.taskListOpenTargetMs, PerformanceBudgets.taskListOpenHardFailMs),
            ("warm-launch", PerformanceBudgets.warmLaunchTargetMs, PerformanceBudgets.warmLaunchHardFailMs)
        ]
        var scores: [Double] = []
        for (name, target, hard) in scenarios {
            let score = PerformanceBudgets.score(durationMs: target * 0.5, targetMs: target, hardFailMs: hard)
            XCTAssertEqual(score, 100, accuracy: 0.01, name)
            scores.append(score)
        }
        let composite = scores.reduce(0, +) / Double(scores.count)
        XCTAssertGreaterThanOrEqual(composite, 80, "Ship gate composite must be >= 80 when all at target")
    }

    func testJSONPersistenceSortMicrobench_AcceptableOnLinux() {
        // Lightweight proxy for TaskListSorter cost: sort 500 priority tuples.
        struct Item: Comparable {
            let priority: Int
            let scheduled: Double
            let created: Double
            static func < (lhs: Item, rhs: Item) -> Bool {
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                if lhs.scheduled != rhs.scheduled { return lhs.scheduled < rhs.scheduled }
                return lhs.created < rhs.created
            }
        }
        let items = (0..<500).map { i in
            Item(priority: i % 5, scheduled: Double(i % 100), created: Double(i))
        }
        let start = Date()
        let sorted = items.sorted()
        let ms = Date().timeIntervalSince(start) * 1000
        XCTAssertEqual(sorted.count, 500)
        let score = PerformanceBudgets.score(
            durationMs: ms,
            targetMs: PerformanceBudgets.taskSort500TargetMs,
            hardFailMs: PerformanceBudgets.taskSort500HardFailMs
        )
        XCTAssertTrue(
            PerformanceBudgets.isAcceptable(score),
            "500-item sort took \(ms)ms (score \(score))"
        )
    }

    func testLocalJSONRoundTrip_ReturnAndWriteBudgets() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("perf-harness-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        struct TaskDTO: Codable, Equatable {
            var id: String
            var title: String
            var minutes: Int
        }
        let payload = (0..<200).map { TaskDTO(id: "\($0)", title: "T\($0)", minutes: 20 + ($0 % 30)) }
        let url = dir.appendingPathComponent("tasks.json")

        let encodeStart = Date()
        let data = try JSONEncoder().encode(payload)
        let encodeMs = Date().timeIntervalSince(encodeStart) * 1000

        let writeStart = Date()
        try data.write(to: url, options: .atomic)
        let writeMs = Date().timeIntervalSince(writeStart) * 1000

        let loadStart = Date()
        let loadedData = try Data(contentsOf: url)
        let loaded = try JSONDecoder().decode([TaskDTO].self, from: loadedData)
        let loadMs = Date().timeIntervalSince(loadStart) * 1000

        XCTAssertEqual(loaded.count, 200)

        let totalWriteMs = writeMs + encodeMs
        // Fire-and-forget save on main app schedules encode off-thread; encode is lower bound of return cost.
        let returnScore = PerformanceBudgets.score(
            durationMs: encodeMs,
            targetMs: PerformanceBudgets.localSaveReturnTargetMs,
            hardFailMs: PerformanceBudgets.localSaveReturnHardFailMs
        )
        let writeScore = PerformanceBudgets.score(
            durationMs: totalWriteMs,
            targetMs: PerformanceBudgets.localWrite200TasksTargetMs,
            hardFailMs: PerformanceBudgets.localWrite200TasksHardFailMs
        )
        let loadScore = PerformanceBudgets.score(
            durationMs: loadMs,
            targetMs: PerformanceBudgets.localLoad200TasksTargetMs,
            hardFailMs: PerformanceBudgets.localLoad200TasksHardFailMs
        )
        XCTAssertTrue(PerformanceBudgets.isAcceptable(returnScore), "encode \(encodeMs)ms score \(returnScore)")
        XCTAssertTrue(PerformanceBudgets.isAcceptable(writeScore), "write \(totalWriteMs)ms score \(writeScore)")
        XCTAssertTrue(PerformanceBudgets.isAcceptable(loadScore), "load \(loadMs)ms score \(loadScore)")
    }
}
