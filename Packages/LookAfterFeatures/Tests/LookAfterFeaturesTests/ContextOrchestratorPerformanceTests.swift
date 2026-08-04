import XCTest
@testable import LookAfterFeatures
import LookAfterCore
import LookAfterData

/// Measures ContextOrchestrator.refresh batch-update path.
/// Pass: refresh with realistic payload under target; hard fail above budget.
@MainActor
final class ContextOrchestratorPerformanceTests: XCTestCase {

    func testRefresh_WithTypicalDayPayload_WithinBudget() async {
        let orchestrator = ContextOrchestrator(
            environmentProvider: EnvironmentContextProvider(
                calendarProvider: UnavailableCalendarEnvironmentSignalProvider(permissionDenied: false)
            )
        )

        let tasks = makeTasks(count: 40)
        let timeline = makeTimeline(from: tasks.prefix(12))
        let cognitive = CognitiveSnapshot(energyScore: 0.62, availableMinutes: 90)
        let health = HealthSummary(date: Date())

        let start = CFAbsoluteTimeGetCurrent()
        await orchestrator.refresh(
            userId: "perf-user",
            userName: "Perf",
            cognitiveSnapshot: cognitive,
            healthSummary: health,
            flowSurface: nil,
            activeFlowSession: nil,
            heroTask: tasks.first,
            topTasks: Array(tasks.prefix(8)),
            unpurchasedShoppingCount: 2,
            upcomingBills: [],
            lifeTimelineEvents: timeline,
            tomorrowLifeTimelineEvents: [],
            isWeekend: false,
            peakStartHour: 9,
            allTasks: tasks,
            completedTaskIDs: [],
            flowConfidenceScore: 0.7,
            capacityLLMPolicy: .deterministicOnly
        )
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let score = PerformanceBudgets.score(
            durationMs: elapsedMs,
            targetMs: PerformanceBudgets.contextRefreshTargetMs,
            hardFailMs: PerformanceBudgets.contextRefreshHardFailMs
        )

        XCTAssertNotNil(orchestrator.snapshot)
        XCTAssertNotNil(orchestrator.brainState)
        XCTAssertNotNil(orchestrator.briefing)
        XCTAssertTrue(
            PerformanceBudgets.isAcceptable(score),
            "ContextOrchestrator.refresh took \(elapsedMs)ms (score \(score)) — hard fail > \(PerformanceBudgets.contextRefreshHardFailMs)ms"
        )
    }

    func testRefresh_WarmSecondCall_WithinBudget() async {
        let orchestrator = ContextOrchestrator(
            environmentProvider: EnvironmentContextProvider(
                calendarProvider: UnavailableCalendarEnvironmentSignalProvider(permissionDenied: false)
            )
        )
        let tasks = makeTasks(count: 25)

        // Warm-up
        await orchestrator.refresh(
            userId: "perf-user",
            userName: "Perf",
            cognitiveSnapshot: CognitiveSnapshot(energyScore: 0.5, availableMinutes: 60),
            healthSummary: nil,
            flowSurface: nil,
            activeFlowSession: nil,
            heroTask: tasks.first,
            topTasks: Array(tasks.prefix(5)),
            unpurchasedShoppingCount: 0,
            allTasks: tasks,
            capacityLLMPolicy: .deterministicOnly
        )

        let start = CFAbsoluteTimeGetCurrent()
        await orchestrator.refresh(
            userId: "perf-user",
            userName: "Perf",
            cognitiveSnapshot: CognitiveSnapshot(energyScore: 0.55, availableMinutes: 55),
            healthSummary: nil,
            flowSurface: nil,
            activeFlowSession: nil,
            heroTask: tasks.first,
            topTasks: Array(tasks.prefix(5)),
            unpurchasedShoppingCount: 0,
            allTasks: tasks,
            capacityLLMPolicy: .deterministicOnly
        )
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let score = PerformanceBudgets.score(
            durationMs: elapsedMs,
            targetMs: PerformanceBudgets.contextWarmRefreshTargetMs,
            hardFailMs: PerformanceBudgets.contextWarmRefreshHardFailMs
        )

        XCTAssertNotNil(orchestrator.brainState)
        XCTAssertTrue(
            PerformanceBudgets.isAcceptable(score),
            "Warm refresh took \(elapsedMs)ms (score \(score))"
        )
    }

    func testRefresh_PublishesConsistentBatchState() async {
        let orchestrator = ContextOrchestrator(
            environmentProvider: EnvironmentContextProvider(
                calendarProvider: UnavailableCalendarEnvironmentSignalProvider(permissionDenied: false)
            )
        )
        let task = LifeTask(title: "Hero", status: .pending, estimatedMinutes: 25, userId: "u")

        await orchestrator.refresh(
            userId: "u",
            userName: "User",
            cognitiveSnapshot: CognitiveSnapshot(energyScore: 0.7, availableMinutes: 40),
            healthSummary: nil,
            flowSurface: nil,
            activeFlowSession: nil,
            heroTask: task,
            topTasks: [task],
            unpurchasedShoppingCount: 0,
            lifeTimelineEvents: makeTimeline(from: [task]),
            allTasks: [task],
            capacityLLMPolicy: .deterministicOnly
        )

        // Batch update contract: if brainState is set, briefing/snapshot should be set in same pass.
        if orchestrator.brainState != nil {
            XCTAssertNotNil(orchestrator.snapshot)
            XCTAssertNotNil(orchestrator.briefing)
        }
    }

    // MARK: - Fixtures

    private func makeTasks(count: Int) -> [LifeTask] {
        (0..<count).map { i in
            LifeTask(
                title: "Ctx \(i)",
                lifeArea: .work,
                priority: .medium,
                status: .pending,
                estimatedMinutes: 20 + (i % 30),
                userId: "perf-user"
            )
        }
    }

    private func makeTimeline(from tasks: some Collection<LifeTask>) -> [LifeTimelineEvent] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        return tasks.enumerated().map { index, task in
            let start = calendar.date(bySettingHour: 9 + (index % 8), minute: 0, second: 0, of: day) ?? Date()
            return LifeTimelineEvent(
                id: "task-\(task.id)",
                kind: .work,
                title: task.title,
                subtitle: "About \(task.estimatedMinutes) minutes",
                date: start,
                estimatedMinutes: task.estimatedMinutes
            )
        }
    }
