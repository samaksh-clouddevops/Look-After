import Foundation

/// User-reported sleep quality when Apple Health has no overnight data.
public enum ManualSleepRating: String, Codable, Sendable, CaseIterable, Identifiable {
    case awful
    case poor
    case fair
    case good
    case great

    public var id: String { rawValue }

    public var emoji: String {
        switch self {
        case .awful: return "😫"
        case .poor: return "😴"
        case .fair: return "😐"
        case .good: return "🙂"
        case .great: return "✨"
        }
    }

    /// SF Symbol for UI (prefer over emoji for consistent chrome).
    public var systemImage: String {
        switch self {
        case .awful: return "cloud.bolt.fill"
        case .poor: return "moon.zzz.fill"
        case .fair: return "cloud.fill"
        case .good: return "sun.max.fill"
        case .great: return "sparkles"
        }
    }

    public var label: String {
        switch self {
        case .awful: return "Awful"
        case .poor: return "Poor"
        case .fair: return "Fair"
        case .good: return "Good"
        case .great: return "Great"
        }
    }

    /// Maps to planning / context sleep quality bands.
    public var sleepQuality: SleepQuality {
        switch self {
        case .awful, .poor: return .poor
        case .fair: return .fair
        case .good: return .good
        case .great: return .excellent
        }
    }

    /// 0.0–1.0 score aligned with HealthKit sleep quality scale.
    public var qualityScore: Double {
        switch self {
        case .awful: return 0.18
        case .poor: return 0.35
        case .fair: return 0.55
        case .good: return 0.75
        case .great: return 0.92
        }
    }

    public func estimatedMinutes(targetSleepHours: Double = IdealSleepPlanner.defaultTargetSleepHours()) -> Double {
        let target = max(targetSleepHours, 6)
        let hours: Double
        switch self {
        case .awful: hours = max(target - 3.5, 3)
        case .poor: hours = max(target - 2.0, 4)
        case .fair: hours = max(target - 1.0, 5)
        case .good: hours = target
        case .great: hours = min(target + 0.75, 10)
        }
        return hours * 60
    }
}

public struct ManualSleepLogEntry: Codable, Sendable, Equatable {
    public var day: Date
    public var rating: ManualSleepRating
    public var loggedAt: Date

    public init(day: Date, rating: ManualSleepRating, loggedAt: Date = Date()) {
        self.day = day
        self.rating = rating
        self.loggedAt = loggedAt
    }
}

/// Day-scoped UserDefaults store for self-reported sleep.
public enum ManualSleepLogStore {
    private static let entriesKey = "lifeos_manual_sleep_log_v1"
    private static let dismissedDayKey = "lifeos_manual_sleep_dismissed_day"

    public static func entry(for day: Date = Date(), calendar: Calendar = .current) -> ManualSleepLogEntry? {
        let dayStart = calendar.startOfDay(for: day)
        return loadEntries().first { calendar.isDate($0.day, inSameDayAs: dayStart) }
    }

    public static func hasEntry(for day: Date = Date(), calendar: Calendar = .current) -> Bool {
        entry(for: day, calendar: calendar) != nil
    }

    public static func save(rating: ManualSleepRating, on day: Date = Date(), calendar: Calendar = .current) {
        let dayStart = calendar.startOfDay(for: day)
        var entries = loadEntries().filter { !calendar.isDate($0.day, inSameDayAs: dayStart) }
        entries.append(ManualSleepLogEntry(day: dayStart, rating: rating))
        persist(entries)
        UserDefaults.standard.removeObject(forKey: dismissedDayKey)
    }

    public static func dismissForToday(calendar: Calendar = .current) {
        UserDefaults.standard.set(
            calendar.startOfDay(for: Date()).timeIntervalSince1970,
            forKey: dismissedDayKey
        )
    }

    public static func dismissedForToday(calendar: Calendar = .current) -> Bool {
        let value = UserDefaults.standard.double(forKey: dismissedDayKey)
        guard value > 0 else { return false }
        let dismissed = Date(timeIntervalSince1970: value)
        return calendar.isDateInToday(dismissed)
    }

    public static func shouldPrompt(
        healthSummary: HealthSummary?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        if dismissedForToday(calendar: calendar) { return false }
        if hasEntry(for: now, calendar: calendar) { return false }
        if let healthSummary,
           HealthSummaryFreshness.hasLastNightSleep(healthSummary, now: now, calendar: calendar),
           (healthSummary.totalSleepMinutes ?? 0) > 0 {
            return false
        }
        return true
    }

    /// Overlays self-reported sleep onto a HealthKit summary for briefing and planning.
    public static func merged(
        with summary: HealthSummary?,
        for day: Date = Date(),
        calendar: Calendar = .current,
        targetSleepHours: Double = IdealSleepPlanner.defaultTargetSleepHours()
    ) -> HealthSummary? {
        guard let entry = entry(for: day, calendar: calendar) else { return summary }
        var merged = summary ?? HealthSummary(date: calendar.startOfDay(for: day))
        merged.date = calendar.startOfDay(for: day)
        merged.totalSleepMinutes = entry.rating.estimatedMinutes(targetSleepHours: targetSleepHours)
        merged.sleepQualityScore = entry.rating.qualityScore
        merged.wakeTime = entry.loggedAt
        return merged
    }

    public static func resetForFactoryReset() {
        UserDefaults.standard.removeObject(forKey: entriesKey)
        UserDefaults.standard.removeObject(forKey: dismissedDayKey)
    }

    private static func loadEntries() -> [ManualSleepLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: entriesKey),
              let decoded = try? JSONDecoder().decode([ManualSleepLogEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func persist(_ entries: [ManualSleepLogEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: entriesKey)
    }
}
