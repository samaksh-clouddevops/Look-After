import XCTest
@testable import LifeOSData
import LifeOSCore

@MainActor
final class AnalyticsCacheTests: XCTestCase {

    func testCacheManagerPersistsReports() {
        let userId = "cache-test-\(UUID().uuidString)"
        let manager = AnalyticsCacheManager.shared
        manager.invalidate(userId: userId)

        let snapshot = AnalyticsDailySnapshot(
            id: AnalyticsDailySnapshot.dayKey(for: Date()),
            date: Calendar.current.startOfDay(for: Date()),
            userId: userId,
            tasksCompleted: 3,
            focusMinutes: 45
        )

        let engine = PersonalAnalyticsEngine(fetchBehaviorEvents: { [] })
        let report = engine.buildReport(from: [snapshot], timeframe: .today, userId: userId)

        var bundle = AnalyticsCacheBundle(
            state: AnalyticsCacheState(userId: userId, lastRefreshAt: Date()),
            snapshots: [snapshot],
            reports: [InsightsTimeframe.today.rawValue: report]
        )
        bundle.aiContext = AIContextBuilder.build(snapshots: [snapshot], weeklyReport: report)
        manager.saveBundle(bundle, userId: userId)
        manager.invalidate(userId: userId) // clears memory only path — reload from disk

        let cached = manager.cachedReport(timeframe: .today, userId: userId)
        XCTAssertEqual(cached?.kpis.completedTasksCount, 3)
        XCTAssertNotNil(manager.cachedAIContext(userId: userId))
    }

    func testSnapshotFastPathMatchesDirectAggregation() async {
        let userId = "snapshot-path-\(UUID().uuidString)"
        let today = Calendar.current.startOfDay(for: Date())
        let snapshot = AnalyticsDailySnapshot(
            id: AnalyticsDailySnapshot.dayKey(for: today),
            date: today,
            userId: userId,
            sleepHours: 7.5,
            steps: 8000,
            tasksCompleted: 2,
            focusMinutes: 90,
            focusSessions: 1
        )

        let engine = PersonalAnalyticsEngine(fetchBehaviorEvents: { [] })
        let fromSnapshots = engine.buildReport(from: [snapshot], timeframe: .today, userId: userId)

        XCTAssertEqual(fromSnapshots.kpis.completedTasksCount, 2)
        XCTAssertEqual(fromSnapshots.kpis.totalFocusMinutes, 90)
        XCTAssertEqual(fromSnapshots.kpis.averageSleepHours, 7.5)
        XCTAssertEqual(fromSnapshots.kpis.averageSteps, 8000)
    }

    func testAIContextBuilderProducesCompactSummary() {
        let today = Calendar.current.startOfDay(for: Date())
        let snapshots = (0..<7).compactMap { offset -> AnalyticsDailySnapshot? in
            guard let day = Calendar.current.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return AnalyticsDailySnapshot(
                id: AnalyticsDailySnapshot.dayKey(for: day),
                date: day,
                userId: "ai-context-user",
                sleepHours: 7.0 + Double(offset) * 0.1,
                steps: 5000 + offset * 100,
                tasksCompleted: offset == 0 ? 4 : 1,
                focusMinutes: 30
            )
        }

        let context = AIContextBuilder.build(snapshots: snapshots, weeklyReport: nil)
        XCTAssertNotNil(context.sleepAverage)
        XCTAssertNotNil(context.stepsToday)
        XCTAssertFalse(context.promptBlock.isEmpty)
        XCTAssertTrue(context.promptBlock.contains("CACHED ANALYTICS SUMMARY"))
    }

    func testRefreshSkipsWhenFingerprintsUnchanged() async {
        let userId = "incremental-\(UUID().uuidString)"
        let service = BackgroundAnalyticsService(
            engine: PersonalAnalyticsEngine(fetchBehaviorEvents: { [] }),
            taskRepo: TaskRepository(),
            healthRepo: HealthSummaryRepository(),
            fetchBehaviorEvents: { [] }
        )

        AnalyticsCacheManager.shared.invalidate(userId: userId)
        await service.refreshIfNeeded(userId: userId, trigger: .manual, force: true)
        let firstRefresh = service.lastRefreshAt

        await service.refreshIfNeeded(userId: userId, trigger: .manual, force: false)
        XCTAssertEqual(service.lastRefreshAt, firstRefresh)
    }
}
