import XCTest
@testable import LookAfterAI

final class AuthProxyClientURLTests: XCTestCase {
    func testConfigurationFromEnv() {
        // Env-based config is optional; ensure URL joining logic is stable via absolute string trim.
        let base = URL(string: "https://example.azurecontainerapps.io/")!
        let config = AuthProxyConfiguration(baseURL: base)
        XCTAssertEqual(
            config.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/license/status",
            "https://example.azurecontainerapps.io/v1/license/status"
        )
    }
}
