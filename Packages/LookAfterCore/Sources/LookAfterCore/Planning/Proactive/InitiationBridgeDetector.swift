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
        let micro = UserFacingCopy.microActionMessage(deferralCount: max(result.deferralCount, 1))
        let dayKey = ProactiveDailyBudget.dayKey(for: now, calendar: calendar)
        return ProactiveAction(
            id: "initiation-bridge.\(dayKey).\(result.heroTask.id)",
            kind: .initiationBridge,
            severity: .high,
            message: "\(micro) Start with \"\(result.heroTask.title)\" for 2 minutes?",
            options: ["Start 2-min focus", "Pick another task", "Not now"],
            surface: .banner,
            relatedTaskIDs: [result.heroTask.id],
            expiresAt: Date().addingTimeInterval(20 * 60)
        )
    }
}
