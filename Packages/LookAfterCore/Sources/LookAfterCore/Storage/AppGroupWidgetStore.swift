import Foundation

/// Shared widget snapshot I/O via the App Group **container file**, not `UserDefaults(suiteName:)`.
///
/// File storage avoids CoreFoundation cfprefsd errors when the suite plist is unavailable
/// (`Container: (null)`, `Using kCFPreferencesAnyUser with a container...`).
public enum AppGroupWidgetStore {
    private static let fileName = "widget-snapshot.json"

    /// True when this process can access any known App Group container.
    public static var isAvailable: Bool {
        containerURL() != nil
    }

    /// Preferred container for writes (legacy until modern entitlement is live).
    public static func containerURL() -> URL? {
        for id in WidgetAppGroup.readIdentifiers {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
                return url
            }
        }
        return nil
    }

    private static func snapshotURL(forGroupId id: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: id)?
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private static var snapshotURL: URL? {
        containerURL()?.appendingPathComponent(fileName, isDirectory: false)
    }

    public static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? SharedFormatters.jsonEncoderSeconds.encode(snapshot) else { return }
        // Dual-write modern + legacy when both containers exist (Phase 7.1).
        for id in WidgetAppGroup.readIdentifiers {
            guard let url = snapshotURL(forGroupId: id) else { continue }
            try? data.write(to: url, options: [.atomic])
        }
    }

    public static func load() -> WidgetSnapshot {
        // Prefer modern group, then legacy file, then UserDefaults migration.
        for id in WidgetAppGroup.readIdentifiers {
            if let url = snapshotURL(forGroupId: id),
               let data = try? Data(contentsOf: url),
               let snapshot = try? SharedFormatters.jsonDecoderSeconds.decode(WidgetSnapshot.self, from: data) {
                // Best-effort copy into primary write target.
                if id != WidgetAppGroup.identifier {
                    save(snapshot)
                }
                return snapshot
            }
        }

        if let migrated = migrateLegacyUserDefaults() {
            return migrated
        }

        return .empty
    }

    public static func clear() {
        for id in WidgetAppGroup.readIdentifiers {
            if let url = snapshotURL(forGroupId: id) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        clearLegacyUserDefaults()
    }

    // MARK: - Legacy UserDefaults (one-time migration only)

    private static func migrateLegacyUserDefaults() -> WidgetSnapshot? {
        guard
            let defaults = cachedLegacyDefaults,
            let data = defaults.data(forKey: WidgetAppGroup.snapshotKey),
            let snapshot = try? SharedFormatters.jsonDecoderSeconds.decode(WidgetSnapshot.self, from: data)
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
