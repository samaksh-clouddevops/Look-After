import Foundation

/// Structured micro-start script shown after repeated deferrals.
public struct InitiationScript: Identifiable, Sendable, Equatable {
    public let id: String
    public let taskID: String
    public let taskTitle: String
    public let deferralCount: Int
    public let steps: [String]
    public let durationMinutes: Int
    public let message: String

    public init(
        id: String = UUID().uuidString,
        taskID: String,
        taskTitle: String,
        deferralCount: Int,
        steps: [String],
        durationMinutes: Int = 2,
        message: String
    ) {
        self.id = id
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.deferralCount = deferralCount
        self.steps = steps
        self.durationMinutes = durationMinutes
        self.message = message
    }
}

public enum DeferralRecoveryThresholds {
    public static let scriptThreshold = 2
    public static let microChunkThreshold = 3
}

public extension Notification.Name {
    static let deferralRecoveryScriptReady = Notification.Name("deferralRecoveryScriptReady")
}
