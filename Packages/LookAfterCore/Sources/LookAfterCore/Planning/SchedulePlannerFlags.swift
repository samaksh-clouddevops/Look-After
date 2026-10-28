import Foundation

/// Feature flags for schedule engine rollout.
public enum SchedulePlannerFlags {
    private static let unifiedPlannerKey = "lookafter.schedule.useUnifiedDayPlanner"

    /// When true, `DaySchedulePlanner` replaces the multi-pass drift/assign/cascade pipeline.
    /// Defaults to `true` when the user has not set an explicit preference.
    public static var useUnifiedDayPlanner: Bool {
        get {
            if UserDefaults.standard.object(forKey: unifiedPlannerKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: unifiedPlannerKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: unifiedPlannerKey) }
    }
}
