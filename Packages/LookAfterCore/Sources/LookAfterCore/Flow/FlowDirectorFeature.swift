import Foundation

/// Feature flag for Flow Director scheduling (D2.4 app integration).
public enum FlowDirectorFeature {
    public static let userDefaultsKey = "enableFlowDirector"

    /// When `true`, BrainViewModel uses FlowDirector instead of ExecutiveBrain for scheduling.
    public static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }
}
