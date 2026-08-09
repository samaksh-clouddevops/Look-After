import Foundation

/// Parses clock times from natural-language planning messages.
public enum PlanningTimeParser {
    public static func parseHourMinute(from text: String) -> (hour: Int, minute: Int)? {
        let lower = text.lowercased()

        if let match = lower.range(of: #"(\d{1,2}):(\d{2})\s*(am|pm)?"#, options: .regularExpression) {
            let snippet = String(lower[match])
            let parts = snippet.replacingOccurrences(of: "am", with: " am")
                .replacingOccurrences(of: "pm", with: " pm")
                .split(separator: " ")
            let timeParts = parts[0].split(separator: ":")
            guard timeParts.count == 2,
                  let hour = Int(timeParts[0]),
                  let minute = Int(timeParts[1]) else { return nil }
            if parts.count > 1, parts[1] == "pm", hour < 12 { return (hour + 12, minute) }
            if parts.count > 1, parts[1] == "am", hour == 12 { return (0, minute) }
            return (hour, minute)
        }

        if let match = lower.range(of: #"(\d{1,2})\s*(am|pm)"#, options: .regularExpression) {
            let snippet = String(lower[match])
            let digits = snippet.filter(\.isNumber)
            guard let hour = Int(digits) else { return nil }
            if snippet.contains("pm"), hour < 12 { return (hour + 12, 0) }
            if snippet.contains("am"), hour == 12 { return (0, 0) }
            return (hour, 0)
        }

        if let match = lower.range(of: #"(?:at|to)\s+(\d{1,2})(?:\s|$)"#, options: .regularExpression) {
            let snippet = String(lower[match])
            let digits = snippet.filter(\.isNumber)
            guard let hour = Int(digits), (0...23).contains(hour) else { return nil }
            return (hour, 0)
        }

        return nil
    }
}
