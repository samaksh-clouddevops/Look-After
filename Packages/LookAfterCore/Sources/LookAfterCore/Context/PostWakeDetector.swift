import Foundation

/// Detects when the user likely just woke up — prefers HealthKit wake time after sync.
public enum PostWakeDetector {

    public static let postWakeWindowMinutes = 90
    public static let overnightGapHours = 6.0

    public struct Input: Sendable {
        public var now: Date
        public var wakeTime: Date?
        public var lastBackgroundAt: Date?
        public var dismissedOnDay: Date?
        public var calendar: Calendar

        public init(
            now: Date = Date(),
            wakeTime: Date? = nil,
            lastBackgroundAt: Date? = nil,
            dismissedOnDay: Date? = nil,
            calendar: Calendar = .current
        ) {
            self.now = now
            self.wakeTime = wakeTime
            self.lastBackgroundAt = lastBackgroundAt
            self.dismissedOnDay = dismissedOnDay
            self.calendar = calendar
        }
    }

    public enum DetectionSource: String, Sendable, Equatable {
        case healthKit
        case overnightGap
        case explicitUser
        case none
    }

    public struct Result: Sendable, Equatable {
        public var isPostWake: Bool
        public var wakeTime: Date?
        public var minutesSinceWake: Int?
        public var source: DetectionSource

        public static let inactive = Result(isPostWake: false, wakeTime: nil, minutesSinceWake: nil, source: .none)
    }

    public static func evaluate(_ input: Input) -> Result {
        let calendar = input.calendar
        let startOfToday = calendar.startOfDay(for: input.now)

        if let dismissed = input.dismissedOnDay,
           calendar.isDate(dismissed, inSameDayAs: input.now) {
            return .inactive
        }

        if let explicit = PostWakeSessionStore.explicitWakeTime(for: input.now, calendar: calendar) {
            let minutes = Int(input.now.timeIntervalSince(explicit) / 60)
            if minutes >= 0, minutes <= postWakeWindowMinutes {
                return Result(
                    isPostWake: true,
                    wakeTime: explicit,
                    minutesSinceWake: minutes,
                    source: .explicitUser
                )
            }
        }

        if let wake = input.wakeTime, calendar.isDate(wake, inSameDayAs: input.now) {
            let minutes = Int(input.now.timeIntervalSince(wake) / 60)
            if minutes >= 0, minutes <= postWakeWindowMinutes {
                return Result(
                    isPostWake: true,
                    wakeTime: wake,
                    minutesSinceWake: minutes,
                    source: .healthKit
                )
            }
        }

        let hour = calendar.component(.hour, from: input.now)
        if (5...11).contains(hour),
           let lastBackground = input.lastBackgroundAt,
           lastBackground < startOfToday || input.now.timeIntervalSince(lastBackground) >= overnightGapHours * 3600 {
            return Result(
                isPostWake: true,
                wakeTime: input.wakeTime,
                minutesSinceWake: input.wakeTime.map { Int(input.now.timeIntervalSince($0) / 60) },
                source: .overnightGap
            )
        }

        return .inactive
    }
}

/// Persists foreground/background timestamps for post-wake heuristics.
public enum PostWakeSessionStore {
    private static let lastBackgroundKey = "lifeos_post_wake_last_background"
    private static let dismissedDayKey = "lifeos_post_wake_dismissed_day"
    private static let explicitWakeKey = "lifeos_post_wake_explicit_wake"

    public static func recordBackground(at date: Date = Date()) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: lastBackgroundKey)
    }

    public static func lastBackgroundAt() -> Date? {
        let value = UserDefaults.standard.double(forKey: lastBackgroundKey)
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    public static func dismissForToday(calendar: Calendar = .current) {
        UserDefaults.standard.set(
            calendar.startOfDay(for: Date()).timeIntervalSince1970,
            forKey: dismissedDayKey
        )
    }

    public static func dismissedOnDay(calendar: Calendar = .current) -> Date? {
        let value = UserDefaults.standard.double(forKey: dismissedDayKey)
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    public static func recordExplicitWake(at date: Date = Date()) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: explicitWakeKey)
    }

    public static func explicitWakeTime(for day: Date = Date(), calendar: Calendar = .current) -> Date? {
        let value = UserDefaults.standard.double(forKey: explicitWakeKey)
        guard value > 0 else { return nil }
        let wake = Date(timeIntervalSince1970: value)
        guard calendar.isDate(wake, inSameDayAs: day) else { return nil }
        return wake
    }

    public static func resetForFactoryReset() {
        UserDefaults.standard.removeObject(forKey: lastBackgroundKey)
        UserDefaults.standard.removeObject(forKey: dismissedDayKey)
        UserDefaults.standard.removeObject(forKey: explicitWakeKey)
    }
}
