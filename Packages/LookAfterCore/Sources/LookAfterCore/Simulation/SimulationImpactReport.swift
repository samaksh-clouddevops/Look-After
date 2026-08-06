import Foundation

// MARK: - Simulation Impact Report

/// Delta between a baseline `LifeState` and a dry-run simulated schedule.
/// Positive parked/superseded deltas mean *more* tasks were displaced by the hypothetical.
public struct SimulationImpactReport: Codable, Equatable, Sendable {
    /// How many *more* tasks were parked vs baseline cascade.
    public var parkedTaskDelta: Int
    /// Sabotage / recovery auctions projected by the simulated load streak.
    public var sabotageAuctionsTriggered: Int
    /// How many *more* tasks were superseded vs baseline.
    public var supersededTasksDelta: Int
    /// Change in consecutive high-load day streak (simulated − baseline).
    public var highLoadStreakDelta: Int
    /// Convenience: absolute parked count after simulation.
    public var simulatedParkedCount: Int
    /// Convenience: absolute superseded count after simulation.
    public var simulatedSupersededCount: Int
    /// Hypothetical task IDs that were injected for this run.
    public var hypotheticalTaskIDs: [String]
    /// Human-facing one-liner derived from the deltas.
    public var summaryMessage: String
    /// Visual severity for the impact banner.
    public var severity: Severity

    public enum Severity: String, Codable, Equatable, Sendable {
        case success
        case neutral
        case warning
        case critical
    }

    public init(
        parkedTaskDelta: Int = 0,
        sabotageAuctionsTriggered: Int = 0,
        supersededTasksDelta: Int = 0,
        highLoadStreakDelta: Int = 0,
        simulatedParkedCount: Int = 0,
        simulatedSupersededCount: Int = 0,
        hypotheticalTaskIDs: [String] = [],
        summaryMessage: String = "",
        severity: Severity = .neutral
    ) {
        self.parkedTaskDelta = parkedTaskDelta
        self.sabotageAuctionsTriggered = sabotageAuctionsTriggered
        self.supersededTasksDelta = supersededTasksDelta
        self.highLoadStreakDelta = highLoadStreakDelta
        self.simulatedParkedCount = simulatedParkedCount
        self.simulatedSupersededCount = simulatedSupersededCount
        self.hypotheticalTaskIDs = hypotheticalTaskIDs
        self.summaryMessage = summaryMessage
        self.severity = severity
    }

    /// True when the schedule absorbed the hypothetical without material displacement.
    public var absorbsSmoothly: Bool {
        parkedTaskDelta <= 0
            && supersededTasksDelta <= 0
            && highLoadStreakDelta <= 0
            && sabotageAuctionsTriggered == 0
    }

    /// True when parked or high-load deltas are materially negative for the user.
    public var isHighlyNegative: Bool {
        parkedTaskDelta >= 2 || highLoadStreakDelta >= 2 || sabotageAuctionsTriggered > 0
    }
}

// MARK: - Simulation Result

/// Full in-memory outcome of a what-if run — never written to persistent stores.
public struct SimulationResult: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var simulatedState: LifeState
    public var impact: SimulationImpactReport
    public var baselineState: LifeState
    /// Day the reconcile was evaluated against.
    public var day: Date
    /// Hypothetical tasks that were injected (pre-cascade copies).
    public var hypotheticalTasks: [LifeTask]

    public init(
        id: String = UUID().uuidString,
        simulatedState: LifeState,
        impact: SimulationImpactReport,
        baselineState: LifeState,
        day: Date,
        hypotheticalTasks: [LifeTask] = []
    ) {
        self.id = id
        self.simulatedState = simulatedState
        self.impact = impact
        self.baselineState = baselineState
        self.day = day
        self.hypotheticalTasks = hypotheticalTasks
    }
}
