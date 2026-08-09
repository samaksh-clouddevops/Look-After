import Foundation

public enum ExperimentReminderStore {
    private static let key = "lookafter.weekly.experiment"

    public struct StoredExperiment: Codable, Sendable, Equatable {
        public var weekKey: String
        public var experiment: String
    }

    public static func save(experiment: String, weekKey: String) {
        let payload = StoredExperiment(weekKey: weekKey, experiment: experiment)
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    public static func load() -> StoredExperiment? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(StoredExperiment.self, from: data) else { return nil }
        return decoded
    }

    public static func resetForFactoryReset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Monday AM reminder for last week's retrospective experiment.
public enum ExperimentFollowThroughDetector {
    public static func evaluate(now: Date = Date(), calendar: Calendar = .current) -> ProactiveAction? {
        guard calendar.component(.weekday, from: now) == 2 else { return nil }
        guard calendar.component(.hour, from: now) >= 7, calendar.component(.hour, from: now) <= 11 else { return nil }
        guard let stored = ExperimentReminderStore.load(), !stored.experiment.isEmpty else { return nil }
        let currentWeek = weekKey(for: now, calendar: calendar)
        guard stored.weekKey != currentWeek else { return nil }
        return ProactiveAction(
            kind: .experimentReminder,
            severity: .medium,
            message: "Try this week: \(stored.experiment)",
            options: ["Add to plan", "Snooze", "Skip"],
            surface: .banner,
            metadata: ["experiment": stored.experiment, "weekKey": stored.weekKey]
        )
    }

    public static func weekKey(for date: Date, calendar: Calendar) -> String {
        let week = calendar.component(.weekOfYear, from: date)
        let year = calendar.component(.yearForWeekOfYear, from: date)
        return "\(year)-W\(week)"
    }
}
