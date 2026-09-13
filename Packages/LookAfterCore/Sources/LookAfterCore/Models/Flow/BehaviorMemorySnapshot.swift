import Foundation

/// A single inferred behavioral pattern stored by Behavior Memory.
public struct BehaviorPattern: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var category: BehaviorPatternCategory
    public var summary: String
    /// Confidence in this pattern (0.0–1.0).
    public var confidence: Double
    public var lastObservedAt: Date

    public init(
        id: String = UUID().uuidString,
        category: BehaviorPatternCategory,
        summary: String,
        confidence: Double,
        lastObservedAt: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.summary = summary
        self.confidence = min(max(confidence, 0), 1)
        self.lastObservedAt = lastObservedAt
    }
}

/// Categories of on-device behavioral inference.
public enum BehaviorPatternCategory: String, Codable, Sendable, CaseIterable {
    case completionContext
    case deferralPattern
    case energyCorrelation
    case durationAccuracy
    case recoveryPattern
    case contextPreference
}

/// Confidence band for a deterministically-inferred numeric pattern (e.g. typical hour,
/// preferred duration). Gated on both sample size and distribution concentration —
/// see `BehaviorMemorySnapshotBuilder` for the exact thresholds.
public enum PatternConfidence: String, Codable, Sendable, CaseIterable, Comparable {
    case low
    case medium
    case high

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    public static func < (lhs: PatternConfidence, rhs: PatternConfidence) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// Deferral record for a specific task, used to trigger coach moments.
public struct TaskDeferralRecord: Codable, Sendable, Equatable {
    public var taskID: String
    public var deferralCount: Int
    public var lastDeferredAt: Date?

    public init(taskID: String, deferralCount: Int = 0, lastDeferredAt: Date? = nil) {
        self.taskID = taskID
        self.deferralCount = max(deferralCount, 0)
        self.lastDeferredAt = lastDeferredAt
    }
}

/// Read-only snapshot consumed by Flow Director during orchestration.
/// Written by `BehaviorMemoryStore` (LookAfterData, milestone D2.2).
public struct BehaviorMemorySnapshot: Codable, Sendable, Equatable {
    /// Inferred patterns (empty until inference milestone; D2.2 collects raw events only).
    public var patterns: [BehaviorPattern]
    /// Aggregated deferral counts derived from raw deferral events.
    public var deferralRecords: [TaskDeferralRecord]
    /// Median `durationMinutes` across `flowSessionEnded` events. Only emitted when
    /// `preferredFlowDurationSampleCount` meets the minimum-sample threshold.
    public var preferredFlowDurationMinutes: Int?
    /// Number of `flowSessionEnded` events the duration median was computed from.
    public var preferredFlowDurationSampleCount: Int?
    /// Confidence band for `preferredFlowDurationMinutes`, gated on sample size and
    /// distribution concentration. `nil` whenever the value itself is `nil`.
    public var preferredFlowDurationConfidence: PatternConfidence?
    /// Mode of `hourOfDay` across long (`durationMinutes >= 30`) `taskCompletion` events.
    /// Represents "typical hour long-focus tasks are completed" — NOT a proven deep-work
    /// preference; it may simply reflect calendar/work-schedule constraints.
    public var typicalDeepWorkHour: Int?
    /// Number of qualifying completion events the hour mode was computed from.
    public var typicalDeepWorkHourSampleCount: Int?
    /// Confidence band for `typicalDeepWorkHour`, gated on sample size and distribution
    /// concentration (mode count / total count). `nil` whenever the value itself is `nil`.
    public var typicalDeepWorkHourConfidence: PatternConfidence?
    /// Total append-only events stored locally.
    public var recordedEventCount: Int
    public var completionEventCount: Int
    public var deferralEventCount: Int
    public var flowSessionEventCount: Int
    public var updatedAt: Date

    public init(
        patterns: [BehaviorPattern] = [],
        deferralRecords: [TaskDeferralRecord] = [],
        preferredFlowDurationMinutes: Int? = nil,
        preferredFlowDurationSampleCount: Int? = nil,
        preferredFlowDurationConfidence: PatternConfidence? = nil,
        typicalDeepWorkHour: Int? = nil,
        typicalDeepWorkHourSampleCount: Int? = nil,
        typicalDeepWorkHourConfidence: PatternConfidence? = nil,
        recordedEventCount: Int = 0,
        completionEventCount: Int = 0,
        deferralEventCount: Int = 0,
        flowSessionEventCount: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.patterns = patterns
        self.deferralRecords = deferralRecords
        self.preferredFlowDurationMinutes = preferredFlowDurationMinutes
        self.preferredFlowDurationSampleCount = preferredFlowDurationSampleCount
        self.preferredFlowDurationConfidence = preferredFlowDurationConfidence
        self.typicalDeepWorkHour = typicalDeepWorkHour
        self.typicalDeepWorkHourSampleCount = typicalDeepWorkHourSampleCount
        self.typicalDeepWorkHourConfidence = typicalDeepWorkHourConfidence
        self.recordedEventCount = max(recordedEventCount, 0)
        self.completionEventCount = max(completionEventCount, 0)
        self.deferralEventCount = max(deferralEventCount, 0)
        self.flowSessionEventCount = max(flowSessionEventCount, 0)
        self.updatedAt = updatedAt
    }

    /// Empty snapshot used until Behavior Memory is populated (D2.2 stub).
    public static let empty = BehaviorMemorySnapshot()

    /// Deferral count for a given task, if tracked.
    public func deferralCount(for taskID: String) -> Int {
        deferralRecords.first { $0.taskID == taskID }?.deferralCount ?? 0
    }
}
