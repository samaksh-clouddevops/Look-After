import Foundation

/// Detects task-initiation paralysis — user opens app repeatedly without starting hero task.
public enum InitiationBridgeDetector {
    public struct Result: Sendable, Equatable {
        public var heroTask: LifeTask
        public var deferralCount: Int
        public var foregroundCount: Int
    }

    public static func analyze(
        heroTask: LifeTask?,
        behaviorMemory: BehaviorMemorySnapshot = .empty,
        foregroundCount: Int,
        focusSessionActive: Bool,
        now: Date = Date()
    ) -> Result? {
        guard !focusSessionActive else { return nil }
        guard foregroundCount >= 5 else { return nil }
        guard let heroTask, heroTask.status.isActive else { return nil }

        let deferrals = behaviorMemory.deferralCount(for: heroTask.id)
        return Result(heroTask: heroTask, deferralCount: deferrals, foregroundCount: foregroundCount)
    }

    public static func proactiveAction(from result: Result, now: Date = Date(), calendar: Calendar = .current) -> ProactiveAction {
        let times = result.deferralCount == 1 ? "once" : "\(max(result.deferralCount, 1)) times"
        let duration = TaskDurationPolicy.microStartDurationPhrase(for: result.heroTask)
        let dayKey = ProactiveDailyBudget.dayKey(for: now, calendar: calendar)
        return ProactiveAction(
            id: "initiation-bridge.\(dayKey).\(result.heroTask.id)",
            kind: .initiationBridge,
            severity: .high,
            message: "You've put this off \(times). Start with \"\(result.heroTask.title)\" for \(duration)?",
            options: [
                TaskDurationPolicy.microStartOptionLabel(for: result.heroTask),
                "Pick another task",
                "Not now"
            ],
            surface: .banner,
            relatedTaskIDs: [result.heroTask.id],
            expiresAt: Date().addingTimeInterval(20 * 60)
        )
    }
}
