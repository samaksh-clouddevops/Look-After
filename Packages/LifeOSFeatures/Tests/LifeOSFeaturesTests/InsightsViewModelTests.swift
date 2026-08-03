import XCTest
@testable import LifeOSFeatures
import LifeOSCore
import LifeOSData

@MainActor
final class InsightsViewModelTests: XCTestCase {

    func testLoadInsightsPopulatesRealReport() async {
        let userId = "insights-vm-user-\(UUID().uuidString)"
        let taskRepo = TaskRepository()
        var task = LifeTask(title: "Analytics task", status: .completed)
        task.completedAt = Date()
        task.userId = userId
        try? await taskRepo.create(task)
        var persisted = task
        persisted.userId = userId
        try? await taskRepo.update(persisted)

        let engine = PersonalAnalyticsEngine(taskRepo: taskRepo, fetchBehaviorEvents: { [] })
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
