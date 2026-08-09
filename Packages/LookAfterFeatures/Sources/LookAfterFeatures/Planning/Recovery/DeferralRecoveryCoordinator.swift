import Foundation
import LookAfterCore
import LookAfterData

/// Holds the latest deferral recovery script for UI presentation.
@MainActor
public enum DeferralRecoveryScriptStore {
    public static var pending: InitiationScript?
}

/// Records deferrals and emits recovery scripts + proactive actions.
@MainActor
public final class DeferralRecoveryCoordinator {
    public static let shared = DeferralRecoveryCoordinator()

    private init() {}

    private func behaviorStore() async -> BehaviorMemoryStore {
        await BehaviorMemoryStore(backend: FileBehaviorMemoryPersistenceBackend())
    }

    /// Call whenever a task is deferred from any surface.
    public func handleDeferral(
        task: LifeTask,
        context: EnvironmentContext? = nil
    ) async -> InitiationScript? {
        let store = await behaviorStore()
        await store.recordDeferral(task: task, context: context)
        let events = await store.fetchEvents()
        let snapshot = BehaviorMemorySnapshotBuilder.build(from: events)
        let count = snapshot.deferralCount(for: task.id)
        guard count >= DeferralRecoveryThresholds.scriptThreshold else { return nil }
        let script = InitiationScriptBuilder.build(task: task, deferralCount: count)
        DeferralRecoveryScriptStore.pending = script
        return script
    }

    public func proactiveAction(from script: InitiationScript) -> ProactiveAction {
        ProactiveAction(
            id: "deferral-recovery-\(script.taskID)",
            kind: .deferralRecovery,
            severity: script.deferralCount >= DeferralRecoveryThresholds.microChunkThreshold ? .high : .medium,
            message: script.message,
            options: ["Start \(script.durationMinutes)-min focus", "Show steps", "Not now"],
            surface: .banner,
            relatedTaskIDs: [script.taskID],
            metadata: [
                "durationMinutes": "\(script.durationMinutes)",
                "deferralCount": "\(script.deferralCount)"
            ]
        )
    }
}
