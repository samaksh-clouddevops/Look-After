import XCTest
@testable import LookAfterData
import LookAfterCore

final class TaskRepositoryMergeTests: XCTestCase {

    func testMergePrefersNewerLocalCopy() {
        let id = "task-1"
        let older = LifeTask(
            id: id,
            title: "Remote",
            status: .pending,
            updatedAt: Date(timeIntervalSince1970: 100),
            userId: "user"
        )
        let newer = LifeTask(
            id: id,
            title: "Local completed",
            status: .completed,
            updatedAt: Date(timeIntervalSince1970: 200),
            completedAt: Date(timeIntervalSince1970: 200),
            userId: "user"
        )

        let merged = TaskMerge.merge(local: [newer], remote: [older])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].status, .completed)
        XCTAssertEqual(merged[0].title, "Local completed")
    }

    func testMergeIncludesLocalOnlyTasks() {
        let localOnly = LifeTask(title: "Local only", userId: "user")
        let remote = LifeTask(title: "Remote", userId: "user")

        let merged = TaskMerge.merge(local: [localOnly], remote: [remote])
        XCTAssertEqual(merged.count, 2)
    }

    func testSnapshotSeparatesActiveAndCompletedToday() {
        var completed = LifeTask(title: "Done", userId: "user")
        completed.status = .completed
        completed.completedAt = Date()

        let pending = LifeTask(title: "Todo", userId: "user")
        let snapshot = TaskListSnapshot.make(from: [completed, pending])

        XCTAssertEqual(snapshot.active.count, 1)
        XCTAssertEqual(snapshot.active[0].title, "Todo")
        XCTAssertEqual(snapshot.completedToday.count, 1)
        XCTAssertEqual(snapshot.completedToday[0].title, "Done")
    }
}
