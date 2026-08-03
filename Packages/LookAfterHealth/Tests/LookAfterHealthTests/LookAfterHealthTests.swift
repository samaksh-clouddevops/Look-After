import XCTest
@testable import LookAfterHealth

final class LookAfterHealthTests: XCTestCase {
    func testHealthFetchStepMetadata() {
        XCTAssertEqual(HealthFetchStep.sleep.title, "Sleep")
        XCTAssertEqual(HealthFetchStep.heartRate.icon, "heart.fill")
        XCTAssertEqual(HealthFetchStep.allCases.count, 5)
        XCTAssertFalse(HealthFetchStep.hrv.explanation.isEmpty)
    }

    @MainActor
    func testHealthManagerInitialState() {
        let manager = HealthManager()

        XCTAssertFalse(manager.isAuthorized)
        XCTAssertNil(manager.latestSummary)
        XCTAssertNil(manager.error)
    }
}
