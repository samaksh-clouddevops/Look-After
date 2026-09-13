import XCTest
@testable import LookAfterData
import LookAfterCore

final class InboxSQLiteStoreTests: XCTestCase {

    func testUpsertLoadDelete() throws {
        let store = InboxSQLiteStore(inMemory: true)
        let user = "inbox_user_1"
        var item = InboxItem(content: "Buy milk", type: .text, userId: user)
        try store.upsert(item)

        var all = try store.loadAll(userId: user)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].content, "Buy milk")

        item.content = "Buy oat milk"
        try store.upsert(item)
        all = try store.loadAll(userId: user)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].content, "Buy oat milk")

        try store.delete(id: item.id)
        XCTAssertTrue(try store.loadAll(userId: user).isEmpty)
    }

    func testUnprocessedFilter() throws {
        let store = InboxSQLiteStore(inMemory: true)
        let user = "inbox_user_2"
        var open = InboxItem(content: "a", status: .unprocessed, userId: user)
        var done = InboxItem(content: "b", status: .archived, userId: user)
        try store.upsert(open)
        try store.upsert(done)
        let unprocessed = try store.loadUnprocessed(userId: user)
        XCTAssertEqual(unprocessed.count, 1)
        XCTAssertEqual(unprocessed[0].content, "a")
    }

    func testReplaceAll() throws {
        let store = InboxSQLiteStore(inMemory: true)
        let user = "inbox_user_3"
        try store.upsert(InboxItem(content: "old", userId: user))
        let fresh = [
            InboxItem(content: "n1", userId: user),
            InboxItem(content: "n2", userId: user),
        ]
        try store.replaceAll(userId: user, items: fresh)
        XCTAssertEqual(try store.loadAll(userId: user).count, 2)
    }
}
