import XCTest
@testable import LookAfterCore

final class HealthSummaryFreshnessTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    func testTodayDatedSummaryCountsAsLastNight() {
        let now = makeDate(year: 2026, month: 8, day: 6, hour: 9, minute: 35)
        var summary = HealthSummary(date: calendar.startOfDay(for: now))
        summary.totalSleepMinutes = 420

        XCTAssertTrue(HealthSummaryFreshness.hasLastNightSleep(summary, now: now, calendar: calendar))
    }

    func testYesterdaySummaryWithoutTodayWakeIsStale() {
        let now = makeDate(year: 2026, month: 8, day: 6, hour: 9, minute: 35)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        var summary = HealthSummary(date: yesterday)
        summary.totalSleepMinutes = 480
        summary.wakeTime = makeDate(year: 2026, month: 8, day: 5, hour: 7, minute: 0)

        XCTAssertFalse(HealthSummaryFreshness.hasLastNightSleep(summary, now: now, calendar: calendar))
    }

    func testForBriefingMetricsStripsStaleSleep() {
        let now = makeDate(year: 2026, month: 8, day: 6, hour: 9, minute: 35)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        var summary = HealthSummary(date: yesterday)
        summary.totalSleepMinutes = 480
        summary.hrvAverage = 55

        let adjusted = HealthSummaryFreshness.forBriefingMetrics(from: summary, now: now, calendar: calendar)
        XCTAssertNil(adjusted?.totalSleepMinutes)
        XCTAssertNil(adjusted?.hrvAverage)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
