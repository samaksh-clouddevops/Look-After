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

    /// Minimum number of qualifying events required before emitting a numeric pattern
    /// value at all. Below this, the signal is treated as insufficient (`nil`), not `.low`.
    private static let minSampleCount = 5
    /// Minimum qualifying-event duration (minutes) for a completion to count toward
    /// `typicalDeepWorkHour` — short tasks don't inform "long-focus" hour preference.
    private static let longTaskMinimumMinutes = 30
    /// Bucket width used to measure duration-distribution concentration for
    /// `preferredFlowDurationMinutes` confidence (does not affect the reported median).
    private static let durationConcentrationBucketMinutes = 15

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

        let hourResult = typicalLongTaskCompletionHour(from: events)
        let durationResult = preferredFlowDuration(from: events)

        return BehaviorMemorySnapshot(
            patterns: [],
            deferralRecords: deferralMap.values.sorted { $0.taskID < $1.taskID },
            preferredFlowDurationMinutes: durationResult?.value,
            preferredFlowDurationSampleCount: durationResult?.sampleCount,
            preferredFlowDurationConfidence: durationResult?.confidence,
            typicalDeepWorkHour: hourResult?.value,
            typicalDeepWorkHourSampleCount: hourResult?.sampleCount,
            typicalDeepWorkHourConfidence: hourResult?.confidence,
            recordedEventCount: events.count,
            completionEventCount: completions,
            deferralEventCount: deferrals,
            flowSessionEventCount: sessions,
            updatedAt: updatedAt
        )
    }

    // MARK: - Typical Long-Task Completion Hour

    /// Mode of `hourOfDay` across `taskCompletion` events with `durationMinutes >= 30`.
    /// Represents "typical hour long-focus tasks are completed" — not a proven deep-work
    /// preference. Returns `nil` below the minimum sample threshold or on a mode tie
    /// (a tie is itself evidence the data doesn't support a single typical hour).
    private static func typicalLongTaskCompletionHour(
        from events: [BehaviorEvent]
    ) -> (value: Int, sampleCount: Int, confidence: PatternConfidence)? {
        let hours = events.compactMap { event -> Int? in
            guard event.kind == .taskCompletion,
                  let duration = event.durationMinutes,
                  duration >= longTaskMinimumMinutes else { return nil }
            return event.context.hourOfDay
        }
        guard let (mode, sampleCount, concentration) = modeWithConcentration(hours) else { return nil }
        guard sampleCount >= minSampleCount else { return nil }
        let confidence = confidenceBand(sampleCount: sampleCount, concentration: concentration)
        return (mode, sampleCount, confidence)
    }

    // MARK: - Preferred Flow Duration

    /// Median `durationMinutes` across `flowSessionEnded` events. Confidence is derived
    /// from how concentrated durations are around a common 15-minute bucket, independent
    /// of the reported median value itself.
    private static func preferredFlowDuration(
        from events: [BehaviorEvent]
    ) -> (value: Int, sampleCount: Int, confidence: PatternConfidence)? {
        let durations = events.compactMap { event -> Int? in
            guard event.kind == .flowSessionEnded else { return nil }
            return event.durationMinutes
        }
        guard durations.count >= minSampleCount, let medianValue = median(durations) else { return nil }

        let buckets = durations.map { $0 / durationConcentrationBucketMinutes }
        guard let (_, sampleCount, concentration) = modeWithConcentration(buckets) else { return nil }
        let confidence = confidenceBand(sampleCount: sampleCount, concentration: concentration)
        return (medianValue, sampleCount, confidence)
    }

    // MARK: - Shared Helpers

    /// Returns the mode (most frequent value), total sample count, and concentration
    /// ratio (`modeCount / totalCount`) for a set of integer values. Returns `nil` if
    /// `values` is empty or the top count is tied across more than one value.
    private static func modeWithConcentration(_ values: [Int]) -> (mode: Int, sampleCount: Int, concentration: Double)? {
        guard !values.isEmpty else { return nil }
        var frequency: [Int: Int] = [:]
        for value in values { frequency[value, default: 0] += 1 }
        guard let maxCount = frequency.values.max() else { return nil }
        let topValues = frequency.filter { $0.value == maxCount }.keys.sorted()
        guard topValues.count == 1, let mode = topValues.first else { return nil }
        let concentration = Double(maxCount) / Double(values.count)
        return (mode, values.count, concentration)
    }

    /// Sample-size- and concentration-gated confidence band.
    /// `sampleCount` is assumed to already be `>= minSampleCount`.
    private static func confidenceBand(sampleCount: Int, concentration: Double) -> PatternConfidence {
        guard sampleCount >= 15 else { return .low }
        if concentration > 0.6 { return .high }
        if concentration >= 0.4 { return .medium }
        return .low
    }

    /// Median of an integer array (average of the two middle values when the count is even,
    /// truncated toward zero to keep the result an `Int`).
    private static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
