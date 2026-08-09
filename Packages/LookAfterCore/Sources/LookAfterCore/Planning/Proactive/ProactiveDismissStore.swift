import Foundation

/// Banner-level snooze/dismiss for proactive kinds (parallel to notification budget).
public enum ProactiveDismissStore {
    private static let snoozeKey = "lookafter.proactive.snooze"
    private static let dismissedKindsKey = "lookafter.proactive.dismissed_kinds"

    public static func snooze(kind: ProactiveAction.Kind, until: Date) {
        var map = loadSnoozeMap()
        map[kind.rawValue] = until
        saveSnoozeMap(map)
    }

    public static func dismissKindForToday(kind: ProactiveAction.Kind, now: Date = Date(), calendar: Calendar = .current) {
        let dayKey = ProactiveDailyBudget.dayKey(for: now, calendar: calendar)
        var set = loadDismissedKinds()
        set.insert("\(kind.rawValue)|\(dayKey)")
        saveDismissedKinds(set)
    }

    public static func isSuppressed(_ action: ProactiveAction, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if let until = loadSnoozeMap()[action.kind.rawValue], until > now {
            return true
        }
        let dayKey = ProactiveDailyBudget.dayKey(for: now, calendar: calendar)
        return loadDismissedKinds().contains("\(action.kind.rawValue)|\(dayKey)")
    }

    public static func resetForFactoryReset() {
        UserDefaults.standard.removeObject(forKey: snoozeKey)
        UserDefaults.standard.removeObject(forKey: dismissedKindsKey)
    }

    private static func loadSnoozeMap() -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: snoozeKey),
              let decoded = try? JSONDecoder().decode([String: Date].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func saveSnoozeMap(_ map: [String: Date]) {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: snoozeKey)
        }
    }

    private static func loadDismissedKinds() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: dismissedKindsKey),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) else {
            return []
        }
        return decoded
    }

    private static func saveDismissedKinds(_ set: Set<String>) {
        if let data = try? JSONEncoder().encode(set) {
            UserDefaults.standard.set(data, forKey: dismissedKindsKey)
        }
    }
}
