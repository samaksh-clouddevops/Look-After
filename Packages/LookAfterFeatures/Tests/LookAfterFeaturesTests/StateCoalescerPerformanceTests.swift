import XCTest
@testable import LookAfterFeatures

/// Verifies StateCoalescer collapses rapid updates into a single emission.
@MainActor
final class StateCoalescerPerformanceTests: XCTestCase {

    func testRapidUpdatesCollapseToLatestValue() async {
        let coalescer = StateCoalescer(initialValue: 0, delayMilliseconds: 30)

        for i in 1...20 {
            coalescer.update(i)
        }

        // Before delay elapses, value should still be initial (or at most one flush race).
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertTrue(coalescer.value == 0 || coalescer.value == 20)

        // After delay, only the latest value should stick.
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(coalescer.value, 20, "Coalescer must publish only the latest pending value")
    }

    func testFlushPublishesImmediately() {
        let coalescer = StateCoalescer(initialValue: "a", delayMilliseconds: 200)
        coalescer.update("b")
        coalescer.flush("c")
        XCTAssertEqual(coalescer.value, "c")
    }

    func testUpdateOverheadUnderOneMillisecond() {
        let coalescer = StateCoalescer(initialValue: 0, delayMilliseconds: 16)
        let start = CFAbsoluteTimeGetCurrent()
        for i in 0..<100 {
            coalescer.update(i)
        }
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        XCTAssertLessThan(
            elapsedMs,
            50,
            "100 coalescer updates took \(elapsedMs)ms — hard fail > 50ms"
        )
    }
}
