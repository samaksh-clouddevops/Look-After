import XCTest
@testable import LookAfterCore

final class AppGroupIntentStoreTests: XCTestCase {

    override func tearDown() {
        AppGroupIntentStore.clear()
        super.tearDown()
    }

    func testEnqueueAndDequeue() {
        AppGroupIntentStore.enqueue(action: .capture, payload: "Buy milk")
        AppGroupIntentStore.enqueue(action: .deferHero)

        XCTAssertEqual(AppGroupIntentStore.pending().count, 2)

        let drained = AppGroupIntentStore.dequeueAll()
        XCTAssertEqual(drained.count, 2)
        XCTAssertEqual(drained.first?.action, .capture)
        XCTAssertEqual(drained.first?.payload, "Buy milk")
        XCTAssertTrue(AppGroupIntentStore.pending().isEmpty)
    }
}
