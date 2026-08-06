import Foundation
import LookAfterCore

/// Persists widget data in the shared App Group container.
public enum WidgetDataStore {
    public static var isAvailable: Bool { AppGroupWidgetStore.isAvailable }

    public static func save(_ snapshot: WidgetSnapshot) {
        AppGroupWidgetStore.save(snapshot)
    }

    public static func load() -> WidgetSnapshot {
        AppGroupWidgetStore.load()
    }

    public static func clear() {
        AppGroupWidgetStore.clear()
    }
}
