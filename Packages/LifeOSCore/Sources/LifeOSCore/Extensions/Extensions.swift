import Foundation

// MARK: - Date Extensions

extension Date {
    /// Start of the current day (midnight).
    public var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
    
    /// End of the current day (23:59:59).
    public var endOfDay: Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfDay) ?? self
    }
    
    /// Returns the hour component (0-23).
    public var hour: Int {
        Calendar.current.component(.hour, from: self)
    }
    
    /// Returns a human-readable relative time string.
    public var relativeTimeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
    
    /// Returns formatted time string (e.g., "2:30 PM").
    public var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
    
    /// Returns formatted date string (e.g., "Jul 28").
    public var shortDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: self)
    }
    
    /// Whether this date is today.
    public var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
    
    /// Whether this date is in the past.
    public var isPast: Bool {
        self < Date()
    }
    
    /// Returns the number of hours between this date and another.
    public func hoursSince(_ other: Date) -> Double {
        self.timeIntervalSince(other) / 3600
    }
    
    /// Returns a date that is `days` days from now.
    public func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }
}

// MARK: - String Extensions

extension String {
    /// Truncates the string to the specified length, adding "..." if needed.
    public func truncated(to length: Int) -> String {
        if self.count <= length { return self }
        return String(self.prefix(length)) + "..."
    }
    
    /// Returns true if the string contains meaningful content (not just whitespace).
    public var hasContent: Bool {
        !self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Double Extensions

extension Double {
    /// Formats the double as a percentage string (e.g., "75%").
    public var percentageString: String {
        "\(Int(self * 100))%"
    }
    
    /// Formats as hours and minutes (e.g., "6h 30m").
    public var hoursMinutesString: String {
        let hours = Int(self) / 60
        let minutes = Int(self) % 60
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Int Extensions

extension Int {
    /// Formats minutes as a readable duration string (e.g., "1h 30m").
    public var durationString: String {
        if self >= 60 {
            let hours = self / 60
            let mins = self % 60
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
        }
        return "\(self)m"
    }
}
