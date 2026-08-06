import XCTest
@testable import LookAfterCore

final class ADHDFocusChallengeTests: XCTestCase {

    func testLegacyOnboardingStringResolvesToCanonicalRawValue() {
        let resolved = ADHDFocusChallenge.resolve("Task initiation")
        XCTAssertEqual(resolved, .taskInitiation)
        XCTAssertEqual(resolved.rawValue, "taskInitiation")
    }

    func testLegacySettingsStringResolves() {
        XCTAssertEqual(ADHDFocusChallenge.resolve("Task Initiation"), .taskInitiation)
        XCTAssertEqual(ADHDFocusChallenge.resolve("Task Paralysis / Overwhelm"), .overwhelm)
    }
}
