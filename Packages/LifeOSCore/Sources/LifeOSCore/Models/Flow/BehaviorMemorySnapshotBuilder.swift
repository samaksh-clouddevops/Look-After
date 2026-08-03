import Foundation

// MARK: - Analysis Engine (Future Inference)

/// Consumes raw behavioral events and produces read models for Flow Director.
///
/// **Separation of concerns:**
/// - `BehaviorMemoryStore` — append-only event persistence only.
/// - `BehaviorMemorySnapshotBuilder` — deterministic aggregation (counts, deferrals).
/// - `BehaviorAnalysisEngine` — pattern detection and learning (future milestone).
///
/// Flow Director should call: `fetchEvents()` → `analysisEngine.buildSnapshot(from:)` → input.
public protocol BehaviorAnalysisEngineProtocol: Sendable {
    /// Builds a `BehaviorMemorySnapshot` from raw events.
    /// Implementations may add inferred `BehaviorPattern` values; the default engine does not.
    func buildSnapshot(from events: [BehaviorEvent]) async -> BehaviorMemorySnapshot
}

// MARK: - Snapshot Builder (Aggregation Only)

/// Deterministic aggregation of raw events into `BehaviorMemorySnapshot`.
///
/// This is **not** inference — it only counts and groups deferrals.
/// Pattern detection belongs in `BehaviorAnalysisEngineProtocol` implementations.
public enum BehaviorMemorySnapshotBuilder {

    /// Aggregates event counts and deferral records. Never infers patterns.
    public static func build(from events: [BehaviorEvent], updatedAt: Date = Date()) -> BehaviorMemorySnapshot {
        var deferralMap: [String: TaskDeferralRecord] = [:]

        for event in events where event.kind == .taskDeferral {
            guard let taskID = event.taskID else { continue }
            var existing = deferralMap[taskID] ?? TaskDeferralRecord(taskID: taskID)
            existing.deferralCount += 1
            existing.lastDeferredAt = event.recordedAt
            deferralMap[taskID] = existing
        }

        let completions = events.filter { $0.kind == .taskCompletion }.count
        let deferrals = events.filter { $0.kind == .taskDeferral }.count
        let sessions = events.filter { $0.kind == .flowSessionEnded }.count

        return BehaviorMemorySnapshot(
            patterns: [],
            deferralRecords: deferralMap.values.sorted { $0.taskID < $1.taskID },
            preferredFlowDurationMinutes: nil,
            typicalDeepWorkHour: nil,
            recordedEventCount: events.count,
            completionEventCount: completions,
            deferralEventCount: deferrals,
            flowSessionEventCount: sessions,
            updatedAt: updatedAt
        )
    }
}
