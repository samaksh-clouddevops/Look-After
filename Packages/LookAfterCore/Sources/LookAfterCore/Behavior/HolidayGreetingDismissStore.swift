import Foundation

/// Tracks whether the once-a-day holiday greeting popup has already been shown/dismissed.
/// Holidays are surfaced only as a one-time greeting card — never as tasks or timeline rows.
public enum HolidayGreetingDismissStore {
    private static let dismissedDayKey = "lookafter_holiday_greeting_dismissed_day"

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
}
