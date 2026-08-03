import Foundation
import LifeOSCore

/// Default analysis engine — aggregation only until inference milestone.
///
/// Delegates to `BehaviorMemorySnapshotBuilder`. Does not detect patterns.
public struct DefaultBehaviorAnalysisEngine: BehaviorAnalysisEngineProtocol {

    public init() {}

    public func buildSnapshot(from events: [BehaviorEvent]) async -> BehaviorMemorySnapshot {
        BehaviorMemorySnapshotBuilder.build(from: events)
    }
}
