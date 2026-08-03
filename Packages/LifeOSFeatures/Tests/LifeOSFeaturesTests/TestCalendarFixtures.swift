import Foundation

/// Fixed UTC calendar and dates for deterministic LifeOSFeatures tests.
enum TestCalendarFixtures {
    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    /// Friday 2026-07-31 12:00 UTC — stable "today" for interaction tests.
    static var today: Date {
        date(year: 2026, month: 7, day: 31, hour: 12)
    }

    static func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
