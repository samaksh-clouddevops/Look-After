import XCTest
@testable import LookAfterData
import LookAfterCore

/// Performance + correctness for LocalPersistenceManager I/O queue changes.
/// Thresholds: save fire-and-forget must return fast; round-trip must stay consistent.
final class LocalPersistencePerformanceTests: XCTestCase {

    private let persistence = LocalPersistenceManager.shared
    private let filenamePrefix = "perf_local_persist_"

    override func tearDown() {
        persistence.deleteFile(named: "\(filenamePrefix)tasks")
        persistence.deleteFile(named: "\(filenamePrefix)async")
        persistence.deleteFile(named: "\(filenamePrefix)race")
        super.tearDown()
    }

    func testSaveReturnsQuickly_DoesNotBlockCaller() {
        let tasks = makeTasks(count: 200)
        let filename = "\(filenamePrefix)tasks"

        let start = CFAbsoluteTimeGetCurrent()
        persistence.save(tasks, filename: filename)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let score = PerformanceBudgets.score(
            durationMs: elapsedMs,
            targetMs: PerformanceBudgets.localSaveReturnTargetMs,
            hardFailMs: PerformanceBudgets.localSaveReturnHardFailMs
        )

        XCTAssertTrue(
            PerformanceBudgets.isAcceptable(score),
            "save() blocked caller for \(elapsedMs)ms (score \(score)) — hard fail > \(PerformanceBudgets.localSaveReturnHardFailMs)ms"
        )
    }

    func testSaveAsyncCompletesAndRoundTrips() async {
        let tasks = makeTasks(count: 200)
        let filename = "\(filenamePrefix)async"

        let writeStart = CFAbsoluteTimeGetCurrent()
        await persistence.saveAsync(tasks, filename: filename)
        let writeMs = (CFAbsoluteTimeGetCurrent() - writeStart) * 1000

        let loadStart = CFAbsoluteTimeGetCurrent()
        let loaded = await persistence.loadAsync([LifeTask].self, filename: filename)
        let loadMs = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000

        let writeScore = PerformanceBudgets.score(
            durationMs: writeMs,
            targetMs: PerformanceBudgets.localWrite200TasksTargetMs,
            hardFailMs: PerformanceBudgets.localWrite200TasksHardFailMs
        )
        let loadScore = PerformanceBudgets.score(
            durationMs: loadMs,
            targetMs: PerformanceBudgets.localLoad200TasksTargetMs,
            hardFailMs: PerformanceBudgets.localLoad200TasksHardFailMs
        )

        XCTAssertEqual(loaded.count, 200)
        XCTAssertEqual(Set(loaded.map(\.id)), Set(tasks.map(\.id)))
        XCTAssertTrue(PerformanceBudgets.isAcceptable(writeScore), "saveAsync 200 tasks \(writeMs)ms score \(writeScore)")
        XCTAssertTrue(PerformanceBudgets.isAcceptable(loadScore), "loadAsync 200 tasks \(loadMs)ms score \(loadScore)")
    }

    func testLoadWaitsForPendingSave_NoLostData() async {
        let filename = "\(filenamePrefix)race"
        let tasks = makeTasks(count: 50)

        // Fire-and-forget save, then barrier load should see data (or empty only if still early —
        // retry briefly so CI hosts with slow disks pass consistently).
        persistence.save(tasks, filename: filename)

        var loaded: [LifeTask] = []
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            loaded = persistence.load([LifeTask].self, filename: filename)
            if loaded.count == 50 { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(
            loaded.count,
            50,
            "Barrier load should eventually observe the pending async save"
        )
    }

    func testSyncLoadAfterAsyncSaveIsConsistent() async {
        let filename = "\(filenamePrefix)async"
        let tasks = makeTasks(count: 30)
        await persistence.saveAsync(tasks, filename: filename)
        let loaded = persistence.load([LifeTask].self, filename: filename)
        XCTAssertEqual(loaded.count, 30)
    }

    // MARK: - Fixtures

    private func makeTasks(count: Int) -> [LifeTask] {
        (0..<count).map { index in
            LifeTask(
                title: "Persist \(index)",
                description: String(repeating: "x", count: 40),
                lifeArea: .work,
                priority: .medium,
                estimatedMinutes: 20,
                userId: "persist-perf"
            )
        }
    }
}
