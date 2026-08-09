import Foundation

/// User preferences for task list AI behavior and scheduling quality.
public enum TaskManagementPreferences {
    private static let smarterFocusTipsKey = "lookafter.smarterFocusTips"
    private static let highQualitySchedulingKey = "lookafter.highQualityScheduling"

    /// When off (default), All Tasks uses local focus-stretch labels only — no background GLM calls.
    public static var smarterFocusTipsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: smarterFocusTipsKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: smarterFocusTipsKey) }
    }

    /// When on (default), day reschedule uses the premium GLM tier (glm-5.2).
    public static var highQualitySchedulingEnabled: Bool {
        get { UserDefaults.standard.object(forKey: highQualitySchedulingKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: highQualitySchedulingKey) }
    }
}
