import Foundation

public enum CyclePreferencesStore {
    public static let userDefaultsKey = "lifeos.cycleTrackingPreferences"

    public static func load() -> CycleTrackingPreferences {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let prefs = try? SharedFormatters.jsonDecoderSeconds.decode(CycleTrackingPreferences.self, from: data) else {
            return .default
        }
        return prefs
    }

    public static func save(_ preferences: CycleTrackingPreferences) {
        if let data = try? SharedFormatters.jsonEncoderSeconds.encode(preferences) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    public static var isEnabled: Bool { load().isEnabled }

    public static var isActive: Bool { CycleFeatureGate.isActive }
}
