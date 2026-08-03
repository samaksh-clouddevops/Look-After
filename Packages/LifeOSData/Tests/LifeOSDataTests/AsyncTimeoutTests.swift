import XCTest
@testable import LifeOSData

final class AsyncTimeoutTests: XCTestCase {
    func testCompletesBeforeTimeout() async throws {
        let value = try await AsyncTimeout.withTimeout(seconds: 1) {
            try await Task.sleep(nanoseconds: 10_000_000)
            return "ok"
        }
        XCTAssertEqual(value, "ok")
    }
    
    func testThrowsWhenTimedOut() async {
        do {
            _ = try await AsyncTimeout.withTimeout(seconds: 0.05) {
                try await Task.sleep(nanoseconds: 500_000_000)
                return true
            }
            XCTFail("Expected timeout")
        } catch is AsyncTimeout.TimeoutError {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
