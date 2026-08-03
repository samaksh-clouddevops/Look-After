import XCTest
@testable import LookAfterFeatures
import LookAfterCore

final class LookAfterFeaturesTests: XCTestCase {
    func testInsightsTimeframeDayCounts() {
        XCTAssertEqual(InsightsTimeframe.last7Days.dayCount, 7)
        XCTAssertEqual(InsightsTimeframe.last30Days.dayCount, 30)
        XCTAssertEqual(InsightsTimeframe.last90Days.dayCount, 90)
        XCTAssertEqual(InsightsTimeframe.lastYear.dayCount, 365)
    }

    func testInsightsSummaryDefaults() {
        let summary = InsightsSummary()

        XCTAssertEqual(summary.timeframe, .last7Days)
        XCTAssertEqual(summary.completedTasksCount, 0)
        XCTAssertEqual(summary.averageExecutiveFunctionScore, 0)
        XCTAssertFalse(summary.hasSufficientData)
    }

    @MainActor
    func testInsightsViewModelInitialState() {
        let viewModel = InsightsViewModel()

        XCTAssertEqual(viewModel.selectedTimeframe, .last7Days)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.isPersonalizationEnabled)
    }
}
