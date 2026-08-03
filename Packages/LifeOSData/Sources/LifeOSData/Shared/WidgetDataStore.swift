import Foundation
import LifeOSCore

/// Persists widget data in the shared App Group container.
public enum WidgetDataStore {
    
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: WidgetAppGroup.identifier)
    }
    
    public static func save(_ snapshot: WidgetSnapshot) {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: WidgetAppGroup.snapshotKey)
        }
    }
    
    public static func load() -> WidgetSnapshot {
        guard
            let defaults,
            let data = defaults.data(forKey: WidgetAppGroup.snapshotKey),
            let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else {
            return .empty
        }
        return snapshot
    }

    public static func clear() {
        guard let defaults else { return }
        defaults.removeObject(forKey: WidgetAppGroup.snapshotKey)
    }
}
