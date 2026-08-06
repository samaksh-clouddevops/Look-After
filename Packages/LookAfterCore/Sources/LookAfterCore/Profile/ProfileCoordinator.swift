import Foundation

/// Single read/write path for display name, peak hours, and onboarding state.
public enum ProfileCoordinator {
    public static var displayName: String {
        UserLifeProfileStore.resolvedDisplayName()
    }

    public static var peakStartHour: Int {
        UserLifeProfileStore.load().peakStartHour
    }

    public static var peakEndHour: Int {
        UserLifeProfileStore.load().peakEndHour
    }

    public static var hasCompletedOnboarding: Bool {
        UserLifeProfileStore.hasCompletedOnboarding
    }

    public static func loadProfile() -> UserLifeProfile {
        UserLifeProfileStore.load()
    }

    public static func saveProfile(_ profile: UserLifeProfile) {
        UserLifeProfileStore.save(profile)
    }

    public static func saveDisplayName(_ name: String) {
        var profile = loadProfile()
        profile.preferredName = name
        saveProfile(profile)
        UserDefaults.standard.set(name, forKey: "userName")
    }

    public static func savePeakHours(start: Int, end: Int) {
        var profile = loadProfile()
        profile.peakStartHour = start
        profile.peakEndHour = end
        saveProfile(profile)
    }
}
