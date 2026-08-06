import Foundation
import LookAfterCore

/// Single store for habit completion history — mirrors `MedicationStore`.
public enum HabitCompletionStore {
    private static let key = "briefingHabitCompletions"

    public static func load() -> [String: [String]] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        if let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            return decoded
        }
        if let legacy = try? JSONDecoder().decode([String: String].self, from: data) {
            let migrated = legacy.mapValues { [$0] }
            save(migrated)
            return migrated
        }
        return [:]
    }

    public static func latestCompletionDates() -> [String: String] {
        load().mapValues { dates in
            dates.sorted().last ?? ""
        }
    }

    public static func save(_ completions: [String: [String]]) {
        if let data = try? JSONEncoder().encode(completions) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    @discardableResult
    public static func toggle(habitId: String, todayKey: String) -> [String: [String]] {
        var completions = load()
        var dates = completions[habitId] ?? []
        if dates.contains(todayKey) {
            dates.removeAll { $0 == todayKey }
        } else {
            dates.append(todayKey)
        }
        if dates.isEmpty {
            completions.removeValue(forKey: habitId)
        } else {
            completions[habitId] = dates.sorted()
        }
        save(completions)
        NotificationCenter.default.post(
            name: .analyticsDataDidChange,
            object: nil,
            userInfo: ["reason": AnalyticsDataChangeReason.habitChanged.rawValue]
        )
        return completions
    }

    public static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
