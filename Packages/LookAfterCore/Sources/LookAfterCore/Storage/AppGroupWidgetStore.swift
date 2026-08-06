import Foundation

/// Shared widget snapshot I/O via the App Group **container file**, not `UserDefaults(suiteName:)`.
///
/// File storage avoids CoreFoundation cfprefsd errors when the suite plist is unavailable
/// (`Container: (null)`, `Using kCFPreferencesAnyUser with a container...`).
public enum AppGroupWidgetStore {
    private static let fileName = "widget-snapshot.json"

    /// True when this process can access the App Group container (entitlements + signing).
    public static var isAvailable: Bool {
        containerURL() != nil
    }

    public static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetAppGroup.identifier)
    }

    private static var snapshotURL: URL? {
        containerURL()?.appendingPathComponent(fileName, isDirectory: false)
    }

    public static func save(_ snapshot: WidgetSnapshot) {
        guard let url = snapshotURL else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Container unavailable or disk full — widget will show stale/empty data.
        }
    }

    public static func load() -> WidgetSnapshot {
        guard isAvailable else { return .empty }

        if let url = snapshotURL,
           let data = try? Data(contentsOf: url),
           let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) {
            return snapshot
        }

        if let migrated = migrateLegacyUserDefaults() {
            return migrated
        }

        return .empty
    }

    public static func clear() {
        if let url = snapshotURL {
            try? FileManager.default.removeItem(at: url)
        }
        clearLegacyUserDefaults()
    }

    // MARK: - Legacy UserDefaults (one-time migration only)

    private static func migrateLegacyUserDefaults() -> WidgetSnapshot? {
        guard
            let defaults = cachedLegacyDefaults,
            let data = defaults.data(forKey: WidgetAppGroup.snapshotKey),
            let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else {
            return nil
        }
        save(snapshot)
        defaults.removeObject(forKey: WidgetAppGroup.snapshotKey)
        return snapshot
    }

    private static func clearLegacyUserDefaults() {
        cachedLegacyDefaults?.removeObject(forKey: WidgetAppGroup.snapshotKey)
    }

    /// Single lazy access — never call `UserDefaults(suiteName:)` on every read/write.
    private static let cachedLegacyDefaults: UserDefaults? = {
        guard isAvailable else { return nil }
        return UserDefaults(suiteName: WidgetAppGroup.identifier)
    }()
}
