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
    /// Reserved for inference milestone.
    public var preferredFlowDurationMinutes: Int?
    /// Reserved for inference milestone.
    public var typicalDeepWorkHour: Int?
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
        typicalDeepWorkHour: Int? = nil,
        recordedEventCount: Int = 0,
        completionEventCount: Int = 0,
        deferralEventCount: Int = 0,
        flowSessionEventCount: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.patterns = patterns
        self.deferralRecords = deferralRecords
        self.preferredFlowDurationMinutes = preferredFlowDurationMinutes
        self.typicalDeepWorkHour = typicalDeepWorkHour
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
