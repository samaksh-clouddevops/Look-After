import XCTest
@testable import LookAfterData
import LookAfterCore

final class InboxSQLiteStoreTests: XCTestCase {
    func testOfflineCreateSurvivesReload() throws {
        let store = InboxSQLiteStore(inMemory: true)
        let item = InboxItem(content: "Capture offline \(UUID().uuidString)", type: .text, userId: "u1")
        try store.upsert(item)
        let loaded = try store.loadAll(for: "u1")
        XCTAssertTrue(loaded.contains(where: { $0.id == item.id }))
        XCTAssertEqual(loaded.filter { $0.id == item.id }.count, 1)
    }

    @MainActor
    func testRepositoryCreateWorksWithoutCloud() async throws {
        let store = InboxSQLiteStore(inMemory: true)
        let repo = InboxRepository(store: store)
        let item = InboxItem(content: "Local only \(UUID().uuidString)", userId: "guest-local")
        try await repo.create(item)
        let local = try store.loadAll(for: "guest-local")
        XCTAssertTrue(local.contains(where: { $0.id == item.id }))
    }
}

final class HealthSummarySQLiteStoreTests: XCTestCase {
    func testUpsertAndLoad() throws {
        let store = HealthSummarySQLiteStore(inMemory: true)
        var summary = HealthSummary(date: Date())
        summary.id = "day-1"
        summary.userId = "u1"
        summary.stepCount = 1000
        try store.upsert(summary)
        let all = try store.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.stepCount, 1000)
    }
}

final class TaskDeletionRegistryTests: XCTestCase {
    func testMarkDeletedPersistsAcrossLoad() {
        TaskDeletionRegistry.reset()
        TaskDeletionRegistry.markDeleted("task-abc")
        XCTAssertTrue(TaskDeletionRegistry.load().contains("task-abc"))
        TaskDeletionRegistry.reset()
        XCTAssertFalse(TaskDeletionRegistry.load().contains("task-abc"))
    }

    func testMergeRemoteAddsIds() {
        TaskDeletionRegistry.reset()
        TaskDeletionRegistry.mergeRemote(["r1", "r2"])
        let ids = TaskDeletionRegistry.load()
        XCTAssertTrue(ids.contains("r1"))
        XCTAssertTrue(ids.contains("r2"))
        TaskDeletionRegistry.reset()
    }
}

final class ModuleEntitySQLiteStoreTests: XCTestCase {
    func testBillRoundTrip() throws {
        let store = ModuleEntitySQLiteStore(inMemory: true)
        let bill = BillItem(title: "Rent", amount: 1200, dueDate: Date(), userId: "u1")
        try store.upsert(bill, collection: .bills, id: bill.id)
        let loaded = try store.loadAll(BillItem.self, collection: .bills)
        XCTAssertEqual(loaded.filter { $0.id == bill.id }.count, 1)
        XCTAssertEqual(loaded.first(where: { $0.id == bill.id })?.title, "Rent")
    }

    func testReplaceAllShopping() throws {
        let store = ModuleEntitySQLiteStore(inMemory: true)
        let a = ShoppingItem(name: "Milk", userId: "u1")
        let b = ShoppingItem(name: "Eggs", userId: "u1")
        try store.replaceAll([a, b], collection: .shoppingItems, id: { $0.id })
        let loaded = try store.loadAll(ShoppingItem.self, collection: .shoppingItems)
        XCTAssertEqual(Set(loaded.map(\.id)), Set([a.id, b.id]))
        try store.delete(collection: .shoppingItems, id: a.id)
        XCTAssertEqual(try store.loadAll(ShoppingItem.self, collection: .shoppingItems).map(\.id), [b.id])
    }
}

final class CloudSyncOutboxTests: XCTestCase {
    @MainActor
    func testEnqueueCoalescesPerDocument() {
        CloudSyncOutbox.shared.resetForTests()
        CloudSyncOutbox.shared.enqueue(
            collection: "inbox_items",
            documentId: "i1",
            userId: "u1",
            operation: .upsert,
            payloadJSON: Data("{}".utf8)
        )
        CloudSyncOutbox.shared.enqueue(
            collection: "inbox_items",
            documentId: "i1",
            userId: "u1",
            operation: .delete,
            payloadJSON: nil
        )
        XCTAssertEqual(CloudSyncOutbox.shared.pendingCount, 1)
        CloudSyncOutbox.shared.resetForTests()
    }
}
