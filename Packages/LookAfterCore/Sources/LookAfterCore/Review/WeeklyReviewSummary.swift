import Foundation

// MARK: - Weekly Review Summary

/// Aggregated outcome of one calendar week of cascade + task activity.
/// Pure value type — produced by `WeeklyReviewAggregator`, consumed by UI.
public struct WeeklyReviewSummary: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var weekStartDate: Date
    public var weekEndDate: Date

    // Core metrics
    public var totalFocusHoursCompleted: Double
    public var timeReclaimedHours: Double
    public var highLoadStreakDays: Int

    // Event counts
    public var sabotageAuctionsTriggered: Int
    public var tasksSupersededCount: Int
    public var tasksExpiredCount: Int
    public var flexibleShiftsExecuted: Int

    /// Equilibrium score in [0.2, 1.0].
    public var equilibriumScore: Double

    public init(
        id: String = UUID().uuidString,
        weekStartDate: Date,
        weekEndDate: Date,
        totalFocusHoursCompleted: Double = 0,
        timeReclaimedHours: Double = 0,
        highLoadStreakDays: Int = 0,
        sabotageAuctionsTriggered: Int = 0,
        tasksSupersededCount: Int = 0,
        tasksExpiredCount: Int = 0,
        flexibleShiftsExecuted: Int = 0,
        equilibriumScore: Double = 0.85
    ) {
        self.id = id
        self.weekStartDate = weekStartDate
        self.weekEndDate = weekEndDate
        self.totalFocusHoursCompleted = totalFocusHoursCompleted
        self.timeReclaimedHours = timeReclaimedHours
        self.highLoadStreakDays = highLoadStreakDays
        self.sabotageAuctionsTriggered = sabotageAuctionsTriggered
        self.tasksSupersededCount = tasksSupersededCount
        self.tasksExpiredCount = tasksExpiredCount
        self.flexibleShiftsExecuted = flexibleShiftsExecuted
        self.equilibriumScore = equilibriumScore
    }

    /// Score as a whole-number percentage for badges.
    public var equilibriumPercent: Int {
        Int((equilibriumScore * 100).rounded())
    }
}

// MARK: - Life State Snapshot (Review input)

/// Lightweight snapshot of operational life state for weekly aggregation.
/// Maps the conceptual LifeEngine active-task surface without coupling Core to UI stores.
public struct LifeState: Codable, Equatable, Sendable {
    public var activeTasks: [LifeTask]
    /// Rolling high-load streak at snapshot time (from WorldState / gap auction context).
    public var consecutiveHighLoadDays: Int

    public init(
        activeTasks: [LifeTask] = [],
        consecutiveHighLoadDays: Int = 0
    ) {
        self.activeTasks = activeTasks
        self.consecutiveHighLoadDays = consecutiveHighLoadDays
    }
}

// MARK: - Cascade Action Record (structured history)

/// Kind of macro cascade event retained for multi-day weekly review.
public enum CascadeActionKind: String, Codable, Sendable, Equatable, CaseIterable {
    case sabotageAuction
    case shiftedLater
    case superseded
    case expired
    case parked
    case compressed
    case deferred
    case other
}

/// Structured cascade log entry with duration metadata for pure weekly aggregation.
public struct CascadeActionRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var kind: CascadeActionKind
    public var timestamp: Date
    /// Minutes associated with the action (shift size, recovery gap, compress delta, etc.).
    public var durationMinutes: Int
    public var taskID: String?
    public var reason: String

    public init(
        id: String = UUID().uuidString,
        kind: CascadeActionKind,
        timestamp: Date = Date(),
        durationMinutes: Int = 0,
        taskID: String? = nil,
        reason: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.durationMinutes = durationMinutes
        self.taskID = taskID
        self.reason = reason
    }
}
