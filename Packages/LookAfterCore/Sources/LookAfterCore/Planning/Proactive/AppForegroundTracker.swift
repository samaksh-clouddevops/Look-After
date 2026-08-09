import Foundation

/// Tracks recent app foreground events for initiation-bridge detection.
public enum AppForegroundTracker {
    private static let timestampsKey = "proactive.appForeground.timestamps"
    private static let maxEntries = 12
    /// Ignore rapid foreground signals (tab switches, view re-appears) within this window.
    private static let minimumIntervalSeconds: TimeInterval = 120

    public static func recordForeground(at date: Date = Date()) {
        var stamps = loadTimestamps()
        if let last = stamps.last,
           date.timeIntervalSince1970 - last < minimumIntervalSeconds {
            return
        }
        stamps.append(date.timeIntervalSince1970)
        if stamps.count > maxEntries {
            stamps = Array(stamps.suffix(maxEntries))
        }
        UserDefaults.standard.set(stamps, forKey: timestampsKey)
    }

    public static func foregroundCount(within minutes: Int, now: Date = Date()) -> Int {
        let cutoff = now.addingTimeInterval(-TimeInterval(minutes * 60))
        return loadTimestamps().filter { Date(timeIntervalSince1970: $0) >= cutoff }.count
    }

    public static func reset() {
        UserDefaults.standard.removeObject(forKey: timestampsKey)
    }

    private static func loadTimestamps() -> [TimeInterval] {
        UserDefaults.standard.array(forKey: timestampsKey) as? [TimeInterval] ?? []
    }
}
