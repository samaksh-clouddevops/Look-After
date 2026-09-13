import XCTest
@testable import LookAfterData
import LookAfterCore

private struct MockTransport: SyncOutboxTransporting, @unchecked Sendable {
    var handler: @Sendable (SyncOutboxRecord) async throws -> Void = { _ in }

    func apply(_ record: SyncOutboxRecord) async throws {
        try await handler(record)
    }
}

@MainActor
final class SyncOutboxStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ArchitectureFeatureFlags.resetAllToDefaults()
        ArchitectureFeatureFlags.useSyncOutbox = true
    }

    override func tearDown() {
        ArchitectureFeatureFlags.resetAllToDefaults()
        super.tearDown()
    }

    func testEnqueueAndDequeue() throws {
        let store = SyncOutboxStore(inMemory: true)
        let user = "user_outbox_1"
        try store.enqueue(
            SyncOutboxRecord(
                userId: user,
                entityType: .task,
                entityId: "t1",
                operation: .upsert,
                payloadJSON: Data(#"{"id":"t1"}"#.utf8)
            )
        )
        XCTAssertEqual(try store.pendingCount(userId: user), 1)

        let ready = try store.dequeueReady(userId: user, limit: 10)
        XCTAssertEqual(ready.count, 1)
        XCTAssertEqual(ready[0].entityId, "t1")
        XCTAssertEqual(ready[0].status, .inFlight)

        try store.markSucceeded(id: ready[0].id)
        XCTAssertEqual(try store.pendingCount(userId: user), 0)
    }

    func testCoalescePendingUpserts() throws {
        let store = SyncOutboxStore(inMemory: true)
        let user = "user_outbox_2"
        try store.enqueue(
            SyncOutboxRecord(userId: user, entityType: .task, entityId: "t2", operation: .upsert, payloadJSON: Data("1".utf8))
        )
        try store.enqueue(
            SyncOutboxRecord(userId: user, entityType: .task, entityId: "t2", operation: .upsert, payloadJSON: Data("2".utf8))
        )
        XCTAssertEqual(try store.pendingCount(userId: user), 1)
        let ready = try store.dequeueReady(userId: user)
        XCTAssertEqual(String(data: ready[0].payloadJSON, encoding: .utf8), "2")
    }

    func testWorkerDrainSuccess() async throws {
        let store = SyncOutboxStore(inMemory: true)
        let user = "user_outbox_3"
        try store.enqueue(
            SyncOutboxRecord(userId: user, entityType: .task, entityId: "t3", operation: .delete)
        )

        var applied = 0
        let transport = MockTransport { _ in applied += 1 }
        let worker = SyncOutboxWorker(store: store, transport: transport)
        let n = await worker.drainOnce(userId: user)
        XCTAssertEqual(n, 1)
        XCTAssertEqual(applied, 1)
        XCTAssertEqual(try store.pendingCount(userId: user), 0)
    }

    func testWorkerBackoffOnFailure() async throws {
        let store = SyncOutboxStore(inMemory: true)
        let user = "user_outbox_4"
        try store.enqueue(
            SyncOutboxRecord(userId: user, entityType: .task, entityId: "t4", operation: .upsert, payloadJSON: Data("{}".utf8))
        )

        struct Boom: Error {}
        let transport = MockTransport { _ in throw Boom() }
        let worker = SyncOutboxWorker(store: store, transport: transport)
        let n = await worker.drainOnce(userId: user)
        XCTAssertEqual(n, 0)
        // Still pending/failed for retry
        XCTAssertEqual(try store.pendingCount(userId: user), 1)
        XCTAssertEqual(SyncOutboxWorker.backoffSeconds(attempt: 1), 2)
        XCTAssertEqual(SyncOutboxWorker.backoffSeconds(attempt: 3), 8)
    }

    func testEnqueueNoopsWhenFlagOff() {
        ArchitectureFeatureFlags.useSyncOutbox = false
        let store = SyncOutboxStore(inMemory: true)
        let worker = SyncOutboxWorker(store: store, transport: MockTransport())
        var task = LifeTask(title: "x")
        task.userId = "u"
        worker.enqueueTaskUpsert(userId: "u", task: task)
        XCTAssertEqual(try? store.pendingCount(userId: "u"), 0)
    }
}
