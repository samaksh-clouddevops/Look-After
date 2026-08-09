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

    public init(cascadeLog: CascadeActionLog = .shared) {
        self.cascadeLog = cascadeLog
    }

    /// Structured cascade history retained in the vault (multi-day).
    public var behavioralVaultHistory: [CascadeActionRecord] {
        cascadeLog.historyRecords()
    }

    /// Build a `LifeState` from task history + the week's high-load streak.
    public func lifeState(
        tasks: [LifeTask],
        weekEnding: Date = Date(),
        calendar: Calendar = .current
    ) -> LifeState {
        let streak = HighLoadDayEvaluator.maxConsecutiveHighLoadDays(
            inWeekEnding: weekEnding,
            tasks: tasks,
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
        let state = lifeState(tasks: tasks, weekEnding: weekEnding, calendar: calendar)
        let logs = cascadeLog.historyRecords()
        return WeeklyReviewAggregator.aggregate(
            logs: logs,
            lifeState: state,
            weekEnding: weekEnding,
            calendar: calendar
        )
    }
}
