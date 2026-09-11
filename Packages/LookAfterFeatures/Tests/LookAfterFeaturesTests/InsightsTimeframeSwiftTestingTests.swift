import Testing
import LookAfterCore
@testable import LookAfterFeatures

struct InsightsTimeframeSwiftTestingTests {
    @Test(arguments: [
        (InsightsTimeframe.last7Days, 7),
        (InsightsTimeframe.last30Days, 30),
        (InsightsTimeframe.last90Days, 90),
        (InsightsTimeframe.lastYear, 365),
    ])
    func dayCountMatchesTimeframe(_ timeframe: InsightsTimeframe, _ expectedDays: Int) {
        #expect(timeframe.dayCount == expectedDays)
    }
}
