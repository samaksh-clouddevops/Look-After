import XCTest
@testable import LifeOSData
import LifeOSCore

final class PersonalAnalyticsEngineTests: XCTestCase {

    @MainActor
    func testBuildReportUsesRealTaskCounts() async {
        let userId = "analytics-test-user-\(UUID().uuidString)"
        let taskRepo = TaskRepository()
        var completed = LifeTask(title: "Ship feature", status: .completed)
        completed.completedAt = Date()
        completed.userId = userId
        try? await taskRepo.create(completed)
        var persisted = completed
        persisted.userId = userId
        try? await taskRepo.update(persisted)

        let engine = PersonalAnalyticsEngine(taskRepo: taskRepo, fetchBehaviorEvents: { [] })
        let report = await engine.buildReport(timeframe: .today, userId: userId)

        XCTAssertEqual(report.kpis.completedTasksCount, 1)
        XCTAssertTrue(report.hasSufficientData)
        XCTAssertFalse(report.insights.isEmpty && report.coachRecommendations.isEmpty)
    }

    @MainActor
    func testEmptyReportDoesNotFabricateKPIs() async {
        let engine = PersonalAnalyticsEngine(
            taskRepo: TaskRepository(),
            healthRepo: HealthSummaryRepository(),
            fetchBehaviorEvents: { [] }
        )
        let report = await engine.buildReport(timeframe: .last7Days, userId: "empty-user-\(UUID().uuidString)")

        XCTAssertNil(report.kpis.completedTasksCount)
        XCTAssertNil(report.kpis.totalFocusMinutes)
        XCTAssertFalse(report.emptyStateMessages.isEmpty)
        XCTAssertTrue(report.charts.filter(\.hasData).isEmpty)
    }

    func testTimeframeDateRanges() {
        let calendar = Calendar.current
        let now = Date()
        let today = InsightsTimeframe.today.dateRange(calendar: calendar, now: now)
        XCTAssertEqual(calendar.startOfDay(for: today.start), today.start)

        let week = InsightsTimeframe.last7Days.dateRange(calendar: calendar, now: now)
        let days = calendar.dateComponents([.day], from: week.start, to: calendar.startOfDay(for: now)).day ?? 0
        XCTAssertEqual(days, 6)
    }
}
