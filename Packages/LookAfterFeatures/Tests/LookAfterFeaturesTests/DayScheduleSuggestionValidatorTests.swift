import XCTest
@testable import LookAfterFeatures

final class DayScheduleSuggestionValidatorTests: XCTestCase {
    @MainActor
    func testFiltersUnknownTaskIDs() {
        let raw = [
            DayScheduleSuggestion(id: "known", startHour: 9, startMinute: 0, reason: "Morning"),
            DayScheduleSuggestion(id: "unknown", startHour: 10, startMinute: 0, reason: "Skip"),
        ]

        let result = DayScheduleSuggestionValidator.validated(raw, allowedTaskIDs: ["known"])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "known")
    }

    @MainActor
    func testDeduplicatesTaskIDsAndTimeSlots() {
        let raw = [
            DayScheduleSuggestion(id: "a", startHour: 9, startMinute: 0),
            DayScheduleSuggestion(id: "a", startHour: 10, startMinute: 0),
            DayScheduleSuggestion(id: "b", startHour: 9, startMinute: 0),
            DayScheduleSuggestion(id: "c", startHour: 25, startMinute: 90),
        ]

        let result = DayScheduleSuggestionValidator.validated(raw, allowedTaskIDs: ["a", "b", "c"])

        XCTAssertEqual(result.map(\.id), ["a", "c"])
        XCTAssertEqual(result[1].startHour, 23)
        XCTAssertEqual(result[1].startMinute, 59)
    }
}
