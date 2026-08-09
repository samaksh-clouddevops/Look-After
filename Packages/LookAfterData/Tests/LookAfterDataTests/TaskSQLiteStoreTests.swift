import XCTest
@testable import LookAfterData
import LookAfterCore

@MainActor
final class TaskSQLiteStoreTests: XCTestCase {

    private var store: TaskSQLiteStore!

    override func setUp() {
        super.setUp()
        store = TaskSQLiteStore(inMemory: true)
    }

    func testRoundTripPreservesLifeTaskFields() throws {
        var task = LifeTask(
            title: "Gym",
            priority: .high,
            scheduledDate: Date(timeIntervalSince1970: 1_700_000_000),
            userId: "user-a"
        )
        task.parentTaskId = "template-1"
        task.isRecurrenceTemplate = false

        try store.replaceAllSync([task])
        let loaded = try store.loadAll()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, task.id)
        XCTAssertEqual(loaded[0].title, "Gym")
        XCTAssertEqual(loaded[0].userId, "user-a")
        XCTAssertEqual(loaded[0].parentTaskId, "template-1")
    }

    func testReplaceAllOverwritesPreviousRows() throws {
        let first = LifeTask(title: "One", userId: "user")
        let second = LifeTask(title: "Two", userId: "user")

        try store.replaceAllSync([first])
        try store.replaceAllSync([second])

        let loaded = try store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].title, "Two")
    }

    func testMigrateFromJSONWhenDatabaseEmpty() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("task-sqlite-migrate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tasks = [
            LifeTask(title: "Legacy A", userId: "legacy-user"),
            LifeTask(title: "Legacy B", userId: "legacy-user")
        ]
        let jsonURL = tempDir.appendingPathComponent("tasks.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(tasks).write(to: jsonURL)

        let dbURL = tempDir.appendingPathComponent("tasks.sqlite")
        let migratedStore = TaskSQLiteStore(databaseURL: dbURL, documentsDirectory: tempDir)

        let loaded = try migratedStore.loadAll()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertTrue(loaded.contains(where: { $0.title == "Legacy A" }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: jsonURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("tasks.json.migrated").path))
    }
}
