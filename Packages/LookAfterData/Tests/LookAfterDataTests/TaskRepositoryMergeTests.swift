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

    func testMergePrefersCompletedOverNewerPending() {
        let id = "task-status"
        let completed = LifeTask(
            id: id,
            title: "Done locally",
            status: .completed,
            updatedAt: Date(timeIntervalSince1970: 100),
            completedAt: Date(timeIntervalSince1970: 100),
            userId: "user"
        )
        let newerPending = LifeTask(
            id: id,
            title: "Stale remote",
            status: .pending,
            updatedAt: Date(timeIntervalSince1970: 500),
            userId: "user"
        )

        let merged = TaskMerge.merge(local: [completed], remote: [newerPending])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].status, .completed)
        XCTAssertEqual(merged[0].title, "Done locally")
    }

    func testMergeDropsDeletedIds() {
        TaskDeletionRegistry.reset()
        TaskDeletionRegistry.markDeleted("gone")
        let remote = LifeTask(id: "gone", title: "Should drop", userId: "user")
        let local = LifeTask(id: "keep", title: "Keep", userId: "user")
        let merged = TaskMerge.merge(local: [local], remote: [remote])
        XCTAssertEqual(merged.map(\.id), ["keep"])
        TaskDeletionRegistry.reset()
    }

    func testMergeKeepsLocalUserPlacedScheduleOverRemoteClock() {
        let id = "task-placed"
        let day = Calendar.current.startOfDay(for: Date())
        let localTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
        let remoteTime = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: day)!
        var local = LifeTask(
            id: id,
            title: "Placed",
            status: .pending,
            scheduledDate: day,
            scheduledTime: localTime,
            updatedAt: Date(timeIntervalSince1970: 100),
            userId: "user"
        )
        local.userPlacedScheduleAt = Date(timeIntervalSince1970: 150)
        var remote = LifeTask(
            id: id,
            title: "Placed",
            status: .pending,
            scheduledDate: day,
            scheduledTime: remoteTime,
            updatedAt: Date(timeIntervalSince1970: 200),
            userId: "user"
        )
        remote.userPlacedScheduleAt = nil

        let merged = TaskMerge.merge(local: [local], remote: [remote])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].scheduledTime, localTime)
        XCTAssertNotNil(merged[0].userPlacedScheduleAt)
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
