import Foundation

/// User preferences for task list AI behavior and scheduling quality.
public enum TaskManagementPreferences {
    private static let smarterFocusTipsKey = "lookafter.smarterFocusTips"
    private static let highQualitySchedulingKey = "lookafter.highQualityScheduling"
    private static let behaviorPersonalizedSchedulingKey = "lookafter.behaviorPersonalizedScheduling"

    /// When off (default), All Tasks uses local focus-stretch labels only — no background GLM calls.
    public static var smarterFocusTipsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: smarterFocusTipsKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: smarterFocusTipsKey) }
    }

    /// When on (default), day reschedule uses the premium GLM tier (glm-5.3).
    public static var highQualitySchedulingEnabled: Bool {
        get { UserDefaults.standard.object(forKey: highQualitySchedulingKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: highQualitySchedulingKey) }
    }

    /// R1 rollout flag (off by default). When on, scheduling prompts include an advisory
    /// behavioral-history block (see `PlanningPromptContextBuilder.behaviorContextBlock`).
    /// Gated separately from `highQualitySchedulingEnabled` per the plan's sequential-rollout
    /// requirement — each AI opportunity ships behind its own flag.
    public static var behaviorPersonalizedSchedulingEnabled: Bool {
        get { UserDefaults.standard.object(forKey: behaviorPersonalizedSchedulingKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: behaviorPersonalizedSchedulingKey) }
    }
}
