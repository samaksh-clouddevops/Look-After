import Foundation

public enum NotificationPreferencesStore {
    public static let userDefaultsKey = "lookafter_notification_preferences"

    public static func load() -> NotificationPreferences {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let prefs = try? JSONDecoder().decode(NotificationPreferences.self, from: data) else {
            return .default
        }
        return prefs
    }

    public static func save(_ preferences: NotificationPreferences) {
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    public static func resetForFactoryReset() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}
