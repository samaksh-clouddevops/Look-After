import Foundation

/// Structured life context the planner uses for scheduling and tone.
public struct UserLifeProfile: Codable, Sendable, Equatable {
    public var hasCompletedOnboarding: Bool
    /// Free-form personality, routines, office timing, and constraints.
    public var profileText: String
    public var workStartHour: Int
    public var workStartMinute: Int
    public var workEndHour: Int
    public var workEndMinute: Int
    public var peakStartHour: Int
    public var peakEndHour: Int
    public var focusTimePreference: FocusTimePreference
    /// Fixed commitments the AI must not move (e.g. "Daily standup 10:00 AM").
    public var fixedScheduleNotes: String
    /// First name extracted from profile text — used when Settings name is empty.
    public var preferredName: String
    /// True after onboarding has created starter tasks from the profile.
    public var hasSeededInitialTasks: Bool
    /// Self-reported gender — used to personalize features like cycle tracking.
    public var gender: UserGender?

    public init(
        hasCompletedOnboarding: Bool = false,
        profileText: String = "",
        workStartHour: Int = 9,
        workStartMinute: Int = 0,
        workEndHour: Int = 18,
        workEndMinute: Int = 0,
        peakStartHour: Int = 9,
        peakEndHour: Int = 12,
        focusTimePreference: FocusTimePreference = .notSure,
        fixedScheduleNotes: String = "",
        preferredName: String = "",
        hasSeededInitialTasks: Bool = false,
        gender: UserGender? = nil
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.profileText = profileText
        self.workStartHour = workStartHour
        self.workStartMinute = workStartMinute
        self.workEndHour = workEndHour
        self.workEndMinute = workEndMinute
        self.peakStartHour = peakStartHour
        self.peakEndHour = peakEndHour
        self.focusTimePreference = focusTimePreference
        self.fixedScheduleNotes = fixedScheduleNotes
        self.preferredName = preferredName
        self.hasSeededInitialTasks = hasSeededInitialTasks
        self.gender = gender
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        profileText = try container.decodeIfPresent(String.self, forKey: .profileText) ?? ""
        workStartHour = try container.decodeIfPresent(Int.self, forKey: .workStartHour) ?? 9
        workStartMinute = try container.decodeIfPresent(Int.self, forKey: .workStartMinute) ?? 0
        workEndHour = try container.decodeIfPresent(Int.self, forKey: .workEndHour) ?? 18
        workEndMinute = try container.decodeIfPresent(Int.self, forKey: .workEndMinute) ?? 0
        peakStartHour = try container.decodeIfPresent(Int.self, forKey: .peakStartHour) ?? 9
        peakEndHour = try container.decodeIfPresent(Int.self, forKey: .peakEndHour) ?? 12
        focusTimePreference = try container.decodeIfPresent(FocusTimePreference.self, forKey: .focusTimePreference) ?? .notSure
        fixedScheduleNotes = try container.decodeIfPresent(String.self, forKey: .fixedScheduleNotes) ?? ""
        preferredName = try container.decodeIfPresent(String.self, forKey: .preferredName) ?? ""
        hasSeededInitialTasks = try container.decodeIfPresent(Bool.self, forKey: .hasSeededInitialTasks) ?? false
        gender = try container.decodeIfPresent(UserGender.self, forKey: .gender)
    }

    /// Apply focus preference → internal peak hours used by schedulers.
    public mutating func syncPeakHoursFromFocusPreference() {
        if focusTimePreference == .notSure { return }
        peakStartHour = focusTimePreference.peakStartHour
        peakEndHour = focusTimePreference.peakEndHour
    }

    public var promptBlock: String {
        var lines: [String] = []
        if !profileText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(profileText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        lines.append("Work hours: \(Self.formatTime(hour: workStartHour, minute: workStartMinute)) – \(Self.formatTime(hour: workEndHour, minute: workEndMinute))")
        if focusTimePreference != .notSure {
            lines.append("Best focus: \(focusTimePreference.label)")
        } else {
            lines.append("Peak energy: \(Self.formatTime(hour: peakStartHour, minute: 0)) – \(Self.formatTime(hour: peakEndHour, minute: 0))")
        }
        if !fixedScheduleNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Fixed timings (never reschedule): \(fixedScheduleNotes.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return lines.joined(separator: "\n")
    }

    /// Afternoon dip window derived from peak end (typical post-lunch lull).
    public var afternoonDipWindowLabel: String {
        let dipStart = min(max(peakEndHour, 0), 23)
        let dipEnd = min(dipStart + 2, 23)
        return "\(Self.formatTime(hour: dipStart, minute: 0)) – \(Self.formatTime(hour: dipEnd, minute: 0))"
    }

    /// Maps to legacy `UserProfile` for cognitive/analytics engines.
    public func toUserProfile(
        displayName: String = "User",
        targetSleepHours: Double = 8.0
    ) -> UserProfile {
        UserProfile(
            displayName: displayName,
            peakEnergyStartHour: peakStartHour,
            peakEnergyEndHour: peakEndHour,
            targetSleepHours: targetSleepHours,
            workStartHour: workStartHour,
            workEndHour: workEndHour,
            preferredTaskDuration: TaskDurationPolicy.softDefaultMinutes
        )
    }

    public static func formatTime(hour: Int, minute: Int) -> String {
        let clampedHour = min(max(hour, 0), 23)
        let clampedMinute = min(max(minute, 0), 59)
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: clampedHour, minute: clampedMinute, second: 0, of: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private enum CodingKeys: String, CodingKey {
        case hasCompletedOnboarding, profileText
        case workStartHour, workStartMinute, workEndHour, workEndMinute
        case peakStartHour, peakEndHour, focusTimePreference, fixedScheduleNotes, preferredName, hasSeededInitialTasks, gender
    }
}

/// Persists the user's life profile for planning.
public enum UserLifeProfileStore {
    public static let storageKey = "lifeos.userLifeProfile"
    private static let userNameDefaultsKey = "userName"
    /// Avoids repeated UserDefaults JSON decode on hot paths (refreshContext, context loop).
    private static var cachedProfile: UserLifeProfile?

    public static func load() -> UserLifeProfile {
        if let cachedProfile { return cachedProfile }
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let profile = try? SharedFormatters.jsonDecoderSeconds.decode(UserLifeProfile.self, from: data) else {
            let migrated = migratedLegacyProfile()
            cachedProfile = migrated
            return migrated
        }
        cachedProfile = profile
        return profile
    }

    public static func save(_ profile: UserLifeProfile) {
        var updated = profile
        refreshPreferredName(on: &updated)

        if let data = try? SharedFormatters.jsonEncoderSeconds.encode(updated) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        UserDefaults.standard.set(updated.peakStartHour, forKey: "peakStartHour")
        UserDefaults.standard.set(updated.peakEndHour, forKey: "peakEndHour")
        cachedProfile = updated
        syncUserNameFromProfileIfNeeded(profile: updated)
    }

    /// Name for greetings and AI — Settings override, then profile, then live extraction.
    public static func resolvedDisplayName() -> String {
        if let manual = UserDefaults.standard.string(forKey: userNameDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !manual.isEmpty {
            return manual
        }

        let profile = load()
        if !profile.preferredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return profile.preferredName
        }

        if let extracted = LifeProfileNameExtractor.extract(profileText: profile.profileText) {
            return extracted
        }

        return ""
    }

    /// Backfills `userName` and `preferredName` for users who only defined their name in profile text.
    /// Never overwrites a non-empty Settings override.
    public static func syncUserNameFromProfileIfNeeded(profile: UserLifeProfile? = nil) {
        let existing = UserDefaults.standard.string(forKey: userNameDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Preserve explicit Settings override regardless of profile content.
        guard existing.isEmpty else { return }

        let profile = profile ?? load()
        let resolved = {
            if !profile.preferredName.isEmpty { return profile.preferredName }
            return LifeProfileNameExtractor.extract(profileText: profile.profileText) ?? ""
        }()

        guard !resolved.isEmpty else { return }
        UserDefaults.standard.set(resolved, forKey: userNameDefaultsKey)
    }

    private static func refreshPreferredName(on profile: inout UserLifeProfile) {
        // Prefer an existing Settings override when profile has no preferredName yet.
        if profile.preferredName.isEmpty {
            if let manual = UserDefaults.standard.string(forKey: userNameDefaultsKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !manual.isEmpty {
                profile.preferredName = manual
                return
            }
        }
        guard let extracted = LifeProfileNameExtractor.extract(profileText: profile.profileText) else { return }
        if profile.preferredName.isEmpty {
            profile.preferredName = extracted
        }
    }

    public static var hasCompletedOnboarding: Bool {
        load().hasCompletedOnboarding
    }

    public static func reset() {
        cachedProfile = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    /// Drops the in-memory cache so the next `load()` re-reads UserDefaults.
    /// Call after bulk UserDefaults wipes (factory reset) that bypass `reset()`.
    public static func invalidateCache() {
        cachedProfile = nil
    }

    public static func loadUserProfile(displayName: String = "User") -> UserProfile {
        let life = load()
        let sleep = UserDefaults.standard.object(forKey: "targetSleepHours") as? Double ?? 8.0
        return life.toUserProfile(displayName: displayName, targetSleepHours: sleep > 0 ? sleep : 8.0)
    }

    public static func remainingWorkMinutes(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let profile = load()
        let elapsed = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let end = profile.workEndHour * 60 + profile.workEndMinute
        if elapsed >= end { return 0 }
        let start = profile.workStartHour * 60 + profile.workStartMinute
        if elapsed < start { return end - start }
        return end - elapsed
    }

    private static func migratedLegacyProfile() -> UserLifeProfile {
        let peakStart = UserDefaults.standard.integer(forKey: "peakStartHour")
        let peakEnd = UserDefaults.standard.integer(forKey: "peakEndHour")
        return UserLifeProfile(
            hasCompletedOnboarding: false,
            peakStartHour: peakStart > 0 ? peakStart : 9,
            peakEndHour: peakEnd > 0 ? peakEnd : 12
        )
    }
}
