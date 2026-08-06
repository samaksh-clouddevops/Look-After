import Foundation

/// User preferences for mirroring scheduled tasks into Apple Calendar.
public enum CalendarSyncSettings {
    public static let syncEnabledKey = "lookafter.calendar.syncTasksToAppleCalendar"

    /// When true, scheduled tasks are written as busy blocks on Apple Calendar.
    public static var syncTasksToAppleCalendar: Bool {
        get {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: syncEnabledKey) == nil { return true }
            return defaults.bool(forKey: syncEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: syncEnabledKey) }
    }
}
