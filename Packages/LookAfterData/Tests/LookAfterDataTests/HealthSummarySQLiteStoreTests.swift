import XCTest
@testable import LookAfterData
import LookAfterCore

final class HealthSummarySQLiteStoreTests: XCTestCase {

    func testUpsertAndLoad() throws {
        let store = HealthSummarySQLiteStore(inMemory: true)
        var summary = HealthSummary()
        summary.id = "u1-2026-08-09"
        summary.userId = "u1"
        summary.date = Date()
        summary.totalSleepMinutes = 420
        try store.upsert(summary)

        let all = try store.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].totalSleepMinutes, 420)
    }

    func testReassignUserId() throws {
        let store = HealthSummarySQLiteStore(inMemory: true)
        var summary = HealthSummary()
        summary.id = "old-day"
        summary.userId = "old"
        summary.date = Date()
        summary.stepCount = 1000
        try store.upsert(summary)

        try store.reassign(from: "old", to: "new")
        let all = try store.loadAll()
        XCTAssertEqual(all[0].userId, "new")
    }
}
