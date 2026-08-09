import XCTest
@testable import LookAfterCore

final class JournalCalibrationSanitizerTests: XCTestCase {

    func testPlainProsePassesThrough() {
        let input = "Writing reports takes about 45 minutes, not 20."
        XCTAssertEqual(JournalCalibrationSanitizer.plainText(from: input), input)
    }

    func testExtractsSummaryFromJSONObject() {
        let input = #"{"summary":"Gym felt easy today; emails drained energy."}"#
        XCTAssertEqual(
            JournalCalibrationSanitizer.plainText(from: input),
            "Gym felt easy today; emails drained energy."
        )
    }

    func testExtractsFromMarkdownWrappedJSON() {
        let input = """
        ```json
        {"calibration":"Music production needs a 90 minute block."}
        ```
        """
        XCTAssertEqual(
            JournalCalibrationSanitizer.plainText(from: input),
            "Music production needs a 90 minute block."
        )
    }

    func testExtractsFromJSONArray() {
        let input = #"["Report took 2 hours", "Brain fog after lunch"]"#
        XCTAssertEqual(
            JournalCalibrationSanitizer.plainText(from: input),
            "Report took 2 hours Brain fog after lunch"
        )
    }

    func testExtractsFromMixedProseAndJSON() {
        let input = """
        Here is the calibration:
        {"response":"Laundry takes longer on low-energy days."}
        """
        XCTAssertEqual(
            JournalCalibrationSanitizer.plainText(from: input),
            "Laundry takes longer on low-energy days."
        )
    }
}

final class SystemImageTests: XCTestCase {
    func testResolvedUsesFallbackForNilAndEmpty() {
        XCTAssertEqual(SystemImage.resolved(nil), "circle")
        XCTAssertEqual(SystemImage.resolved(""), "circle")
        XCTAssertEqual(SystemImage.resolved("   "), "circle")
        XCTAssertEqual(SystemImage.resolved("sparkles", fallback: "circle"), "sparkles")
    }
}
