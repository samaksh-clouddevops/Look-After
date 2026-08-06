import Foundation

// MARK: - Life Engine (Review façade)

/// Centralized read surface for Weekly Review aggregation.
/// Pulls cascade history from the action log (BehavioralVault-adjacent memory)
/// and builds a `LifeState` snapshot for the pure aggregator.
///
/// No UI / no side effects beyond reading shared vaults.
public final class LifeEngine: @unchecked Sendable {
    public static let shared = LifeEngine()

    private let cascadeLog: CascadeActionLog
    private let lock = NSLock()

    public init(cascadeLog: CascadeActionLog = .shared) {
        self.cascadeLog = cascadeLog
    }

    /// Structured cascade history retained in the vault (multi-day).
    public var behavioralVaultHistory: [CascadeActionRecord] {
        cascadeLog.historyRecords()
    }

    /// Build a `LifeState` from operational tasks + high-load streak.
    public func lifeState(
        tasks: [LifeTask],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> LifeState {
        let streak = HighLoadDayEvaluator.consecutiveHighLoadDays(
            tasks: tasks,
            now: now,
            calendar: calendar
        )
        return LifeState(activeTasks: tasks, consecutiveHighLoadDays: streak)
    }

    /// End-to-end pure aggregation for the week ending at `weekEnding`.
    public func weeklyReview(
        tasks: [LifeTask],
        weekEnding: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyReviewSummary {
        let state = lifeState(tasks: tasks, now: weekEnding, calendar: calendar)
        let logs = cascadeLog.historyRecords()
        return WeeklyReviewAggregator.aggregate(
            logs: logs,
            lifeState: state,
            weekEnding: weekEnding,
            calendar: calendar
        )
    }

    /// Build a pure commit intent for tasks produced by a what-if simulation.
    /// Callers (UI / ViewModels) apply the intent against their task stores —
    /// LifeEngine itself never writes to persistence.
    public func commitSimulationIntent(
        from result: SimulationResult
    ) -> SimulationCommitIntent {
        lock.lock()
        defer { lock.unlock() }
        return SimulationCommitIntent(
            tasksToIngest: result.hypotheticalTasks,
            simulatedDay: result.day,
            impact: result.impact,
            generatedAt: Date()
        )
    }
}

// MARK: - Simulation commit intent

/// Value payload asking the operational layer to ingest simulated tasks for real.
public struct SimulationCommitIntent: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var tasksToIngest: [LifeTask]
    public var simulatedDay: Date
    public var impact: SimulationImpactReport
    public var generatedAt: Date

    public init(
        id: String = UUID().uuidString,
        tasksToIngest: [LifeTask],
        simulatedDay: Date,
        impact: SimulationImpactReport,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.tasksToIngest = tasksToIngest
        self.simulatedDay = simulatedDay
        self.impact = impact
        self.generatedAt = generatedAt
    }
}
