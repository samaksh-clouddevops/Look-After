import XCTest
@testable import LookAfterCore

final class UserFacingCopyTests: XCTestCase {
    func testHumanizeBriefingLineDoesNotInfiniteLoopOnRecoveryMode() {
        let input = "You are in recovery mode today. Take it easy."
        let output = UserFacingCopy.humanizeBriefingLine(input)

        XCTAssertFalse(output.contains("in in in"))
        XCTAssertTrue(output.count < 500)
        XCTAssertTrue(output.lowercased().contains("recovery"))
    }

    func testSanitizeStripsInternalLabelsWithoutRunawayGrowth() {
        let input = "Start a focus block and finish your report."
        let output = UserFacingCopy.sanitize(input)

        XCTAssertFalse(output.lowercased().contains("focus block"))
        XCTAssertTrue(output.count < 200)
    }
}
