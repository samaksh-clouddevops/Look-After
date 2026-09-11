import XCTest
@testable import LookAfterFeatures
@testable import LookAfterData
import LookAfterCore

/// Contract checks that do not wipe the developer's on-disk Documents databases.
@MainActor
final class FactoryResetManagerContractTests: XCTestCase {
    func testFreshStartFlagLifecycle() {
        FactoryResetManager.shared.clearPendingFreshStart()
        XCTAssertFalse(FactoryResetManager.shared.isPendingFreshStart)

        UserDefaults.standard.set(true, forKey: FactoryResetPreservation.freshStartFlagKey)
        XCTAssertTrue(FactoryResetManager.shared.isPendingFreshStart)
        FactoryResetManager.shared.clearPendingFreshStart()
        XCTAssertFalse(FactoryResetManager.shared.isPendingFreshStart)
    }

    func testOutboxAndDeletionRegistryClearApisUsedByReset() {
        TaskDeletionRegistry.markDeleted("contract-id")
        XCTAssertTrue(TaskDeletionRegistry.load().contains("contract-id"))
        TaskDeletionRegistry.reset()
        XCTAssertTrue(TaskDeletionRegistry.load().isEmpty)

        var task = LifeTask(title: "Outbox", userId: "contract")
        TaskSyncOutbox.shared.enqueueUpsert(task, merge: false)
        XCTAssertGreaterThanOrEqual(TaskSyncOutbox.shared.pendingCount, 1)
        TaskSyncOutbox.shared.clearAll()
        XCTAssertEqual(TaskSyncOutbox.shared.pendingCount, 0)
    }

    func testInMemoryStoresResetIndependently() throws {
        let inbox = InboxSQLiteStore(inMemory: true)
        try inbox.upsert(InboxItem(content: "x", userId: "u"))
        try inbox.reset()
        XCTAssertTrue(try inbox.loadAll(for: "u").isEmpty)

        let health = HealthSummarySQLiteStore(inMemory: true)
        var summary = HealthSummary(date: Date())
        summary.id = "h1"
        summary.userId = "u"
        try health.upsert(summary)
        try health.reset()
        XCTAssertTrue(try health.loadAll().isEmpty)

        let modules = ModuleEntitySQLiteStore(inMemory: true)
        let bill = BillItem(title: "Net", amount: 10, dueDate: Date(), userId: "u")
        try modules.upsert(bill, collection: .bills, id: bill.id)
        try modules.reset()
        XCTAssertTrue(try modules.loadAll(BillItem.self, collection: .bills).isEmpty)
    }
}
