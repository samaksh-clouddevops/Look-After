import Foundation

/// Formats focus windows for display — never shows impossible precision.
public enum FocusWindowFormatter {

    public static let noStrongWindow = "No strong focus window today"

    /// Rounds to the nearest 5 minutes and rejects zero-length or very short windows.
    public static func displayLabel(for interval: DateInterval, minimumMinutes: Int = 15) -> String {
        let durationMinutes = Int(interval.duration / 60)
        guard durationMinutes >= minimumMinutes else { return noStrongWindow }

        let start = roundToFiveMinutes(interval.start)
        let end = roundToFiveMinutes(interval.end)
        guard end.timeIntervalSince(start) >= Double(minimumMinutes * 60) else { return noStrongWindow }

        return "\(timeFormatter.string(from: start)) – \(timeFormatter.string(from: end))"
    }

    public static func displayLabel(startHour: Int, endHour: Int) -> String {
        let normalizedStart = ((startHour % 24) + 24) % 24
        let normalizedEnd = ((endHour % 24) + 24) % 24
        guard normalizedEnd > normalizedStart else { return noStrongWindow }
        return "\(formatHour(normalizedStart)) – \(formatHour(normalizedEnd))"
    }

    private static func roundToFiveMinutes(_ date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let minute = components.minute else { return date }
        let rounded = (minute / 5) * 5
        var adjusted = components
        adjusted.minute = rounded
        adjusted.second = 0
        return calendar.date(from: adjusted) ?? date
    }

    private static func formatHour(_ hour: Int) -> String {
        let suffix = hour >= 12 ? "PM" : "AM"
        let display = hour % 12 == 0 ? 12 : hour % 12
        return "\(display):00 \(suffix)"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}
