import Foundation
import LookAfterCore

/// Re-export App Group I/O for extensions so they never link Features/Data (Phase 8.1).
public enum LookAfterAppGroupAPI {
    public static var widgetGroupIds: [String] { WidgetAppGroup.readIdentifiers }
    public static var primaryGroupId: String { WidgetAppGroup.identifier }

    public static func loadWidgetSnapshot() -> WidgetSnapshot {
        AppGroupWidgetStore.load()
    }

    public static func saveWidgetSnapshot(_ snapshot: WidgetSnapshot) {
        AppGroupWidgetStore.save(snapshot)
    }

    public static func loadPendingIntents() -> [PendingShortcutRequest] {
        AppGroupIntentStore.pending()
    }
}
