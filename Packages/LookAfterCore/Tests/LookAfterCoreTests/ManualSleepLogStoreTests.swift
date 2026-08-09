import XCTest
@testable import LookAfterCore

final class ManualSleepLogStoreTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    override func tearDown() {
        ManualSleepLogStore.resetForFactoryReset()
        super.tearDown()
    }

    func testSaveAndLoadEntryForToday() {
        ManualSleepLogStore.save(rating: .good)
        let entry = ManualSleepLogStore.entry()
        XCTAssertEqual(entry?.rating, .good)
    }

    func testShouldPromptWhenNoHealthOrManualData() {
        let summary = HealthSummary(date: Date())
        XCTAssertTrue(ManualSleepLogStore.shouldPrompt(healthSummary: summary))
    }

    func testShouldNotPromptAfterManualSave() {
        ManualSleepLogStore.save(rating: .fair)
        XCTAssertFalse(ManualSleepLogStore.shouldPrompt(healthSummary: nil))
    }

    func testMergedOverlaySetsSleepFields() {
        ManualSleepLogStore.save(rating: .poor)
        let merged = ManualSleepLogStore.merged(with: nil)!
        XCTAssertGreaterThan(merged.totalSleepMinutes ?? 0, 0)
        XCTAssertEqual(merged.sleepQualityScore, ManualSleepRating.poor.qualityScore)
        XCTAssertTrue(HealthSummaryFreshness.hasLastNightSleep(merged))
    }

    func testDismissForTodaySuppressesPrompt() {
        ManualSleepLogStore.dismissForToday()
        XCTAssertTrue(ManualSleepLogStore.dismissedForToday())
        XCTAssertFalse(ManualSleepLogStore.shouldPrompt(healthSummary: nil))
    }
}
