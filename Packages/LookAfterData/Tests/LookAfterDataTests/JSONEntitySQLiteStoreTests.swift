import XCTest
@testable import LookAfterData
import LookAfterCore

final class JSONEntitySQLiteStoreTests: XCTestCase {

    func testBillRoundTrip() throws {
        let store = JSONEntitySQLiteStore(inMemoryTable: "bills_test")
        let bill = BillItem(
            title: "Rent",
            amount: 1200,
            dueDate: Date(),
            userId: "u1"
        )
        // BillItem init may vary — encode via upsert with explicit id
        try store.upsert(id: bill.id, userId: "u1", value: bill)
        let loaded: [BillItem] = try store.loadAll(as: BillItem.self, userId: "u1")
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].title, "Rent")
        try store.delete(id: bill.id)
        XCTAssertTrue(try store.loadAll(as: BillItem.self, userId: "u1").isEmpty)
    }
}
