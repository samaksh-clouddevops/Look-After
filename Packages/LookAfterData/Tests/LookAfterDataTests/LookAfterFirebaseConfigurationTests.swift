import XCTest
@testable import LookAfterData

final class LookAfterFirebaseConfigurationTests: XCTestCase {

    func testMockAPIKeyMatchesFirebaseFormat() {
        XCTAssertEqual(LookAfterFirebaseConfiguration.mockAPIKey.count, 39)
        XCTAssertTrue(LookAfterFirebaseConfiguration.mockAPIKey.hasPrefix("A"))
        XCTAssertTrue(LookAfterFirebaseConfiguration.isValidAPIKey(LookAfterFirebaseConfiguration.mockAPIKey))
    }

    func testRejectsShortPlaceholderKeys() {
        XCTAssertFalse(LookAfterFirebaseConfiguration.isValidAPIKey("mock-api-key"))
        XCTAssertFalse(LookAfterFirebaseConfiguration.isValidAPIKey("dummy_api_key"))
        XCTAssertFalse(LookAfterFirebaseConfiguration.isValidAPIKey("AIzaSy0000000000000000000000000000000"))
    }
}
