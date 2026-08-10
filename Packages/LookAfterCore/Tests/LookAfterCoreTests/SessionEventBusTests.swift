import XCTest
@testable import LookAfterCore

final class SessionEventBusTests: XCTestCase {

    func testSubscribeReceivesPublish() async {
        let bus = SessionEventBus()
        let stream = bus.subscribe()

        let expectation = expectation(description: "event")
        let task = Task {
            for await event in stream {
                if case .tasksChanged(let uid) = event {
                    XCTAssertEqual(uid, "u1")
                    expectation.fulfill()
                    break
                }
            }
        }

        // Let subscription register
        await Task.yield()
        bus.publish(.tasksChanged(userId: "u1"))
        await fulfillment(of: [expectation], timeout: 2)
        task.cancel()
    }
}
