import Foundation

/// Controls visibility of menstrual cycle tracking — female users only.
public enum CycleFeatureGate {
    public static var isEligible: Bool {
        UserLifeProfileStore.load().gender == .female
    }

    public static var isActive: Bool {
        isEligible && CyclePreferencesStore.load().isEnabled
    }
}
