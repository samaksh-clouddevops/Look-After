import XCTest
@testable import LookAfterFeatures
import LookAfterCore
import LookAfterData

@MainActor
final class InsightsViewModelTests: XCTestCase {

    func testLoadInsightsPopulatesRealReport() async throws {
        let userId = "insights-vm-user-\(UUID().uuidString)"
        let taskRepo = TaskRepository()
        let task = LifeTask(
            title: "Analytics task",
            status: .completed,
            completedAt: Date(),
            userId: userId
        )
        try await taskRepo.create(task)

        let stored = try await taskRepo.getAll(for: userId)
        XCTAssertTrue(stored.contains(where: { $0.id == task.id }), "Created task should round-trip for userId")

        let engine = PersonalAnalyticsEngine(taskRepo: taskRepo, fetchBehaviorEvents: { [] })
        engine.invalidateCache()
        let viewModel = InsightsViewModel(analyticsEngine: engine, analyticsService: nil, userId: userId)

        await viewModel.loadInsights(for: .today)

        XCTAssertEqual(viewModel.report.kpis.completedTasksCount, 1)
        XCTAssertEqual(viewModel.summary.completedTasksCount, 1)
        XCTAssertFalse(viewModel.summary.personalizationPromptContext.isEmpty)
        XCTAssertTrue(viewModel.summary.personalizationPromptContext.contains("real data only"))
    }

    func testNoFakeEnergyScoreWhenNoHealthData() async {
        let engine = PersonalAnalyticsEngine(fetchBehaviorEvents: { [] })
        let viewModel = InsightsViewModel(
            analyticsEngine: engine,
            analyticsService: nil,
            userId: "no-data-\(UUID().uuidString)"
        )

        await viewModel.loadInsights(for: .last30Days)

        XCTAssertNil(viewModel.report.kpis.averageEnergyScore)
        XCTAssertEqual(viewModel.summary.averageEnergyScore, 0)
    }
}
