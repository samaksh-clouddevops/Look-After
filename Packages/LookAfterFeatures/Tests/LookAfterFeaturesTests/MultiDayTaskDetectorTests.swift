import XCTest
@testable import LookAfterCore
@testable import LookAfterFeatures

final class MultiDayTaskDetectorTests: XCTestCase {

    @MainActor
    func testDetectsSpreadAcrossWeek() {
        let result = MultiDayTaskDetector.detect(in: "I need to spread my presentation prep across the week")
        XCTAssertTrue(result.isMultiDay)
        XCTAssertEqual(result.suggestedDayCount, 5)
    }

    @MainActor
    func testExtractsExplicitDayCount() {
        XCTAssertEqual(MultiDayTaskDetector.extractDayCount(from: "finish in 7 days"), 7)
        XCTAssertEqual(MultiDayTaskDetector.extractDayCount(from: "5-day plan"), 5)
    }

    @MainActor
    func testSingleDayTaskNotDetected() {
        let result = MultiDayTaskDetector.detect(in: "buy milk on the way home")
        XCTAssertFalse(result.isMultiDay)
    }

    @MainActor
    func testInfersCreativeLifeArea() {
        let result = MultiDayTaskDetector.detect(in: "spread music production over several days")
        XCTAssertTrue(result.isMultiDay)
        XCTAssertEqual(result.inferredLifeArea, .creativity)
    }
}
