import Foundation

/// Schedule boundaries inferred from free-form profile text (no AI required).
public struct ExtractedScheduleBoundaries: Sendable, Equatable {
    public var workStartHour: Int?
    public var workStartMinute: Int?
    public var workEndHour: Int?
    public var workEndMinute: Int?
    public var fixedScheduleNotes: String?
    public var focusPreference: FocusTimePreference?

    public init(
        workStartHour: Int? = nil,
        workStartMinute: Int? = nil,
        workEndHour: Int? = nil,
        workEndMinute: Int? = nil,
        fixedScheduleNotes: String? = nil,
        focusPreference: FocusTimePreference? = nil
    ) {
        self.workStartHour = workStartHour
        self.workStartMinute = workStartMinute
        self.workEndHour = workEndHour
        self.workEndMinute = workEndMinute
        self.fixedScheduleNotes = fixedScheduleNotes
        self.focusPreference = focusPreference
    }

    public var hasWorkHours: Bool {
        workStartHour != nil && workEndHour != nil
    }
}

public enum LifeProfileScheduleExtractor {

    /// Extract work hours, fixed events, and focus preference from profile content.
    public static func extract(
        profileText: String,
        sections: StructuredLifeProfileSections? = nil
    ) -> ExtractedScheduleBoundaries {
        let scheduleText = [
            sections?.dailySchedule,
            sections?.planningPreferences,
            sections?.personality,
            sections?.adhdFocusPatterns,
            profileText
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        var result = ExtractedScheduleBoundaries()
        result.focusPreference = FocusTimePreference.infer(from: scheduleText)

        if let hours = extractWorkHours(from: scheduleText) {
            result.workStartHour = hours.startHour
            result.workStartMinute = hours.startMinute
            result.workEndHour = hours.endHour
            result.workEndMinute = hours.endMinute
        }

        let fixed = extractFixedCommitments(from: scheduleText)
        if !fixed.isEmpty {
            result.fixedScheduleNotes = fixed.joined(separator: "; ")
        }

        return result
    }

    // MARK: - Work hours

    private struct ParsedWorkHours {
        var startHour: Int
        var startMinute: Int
        var endHour: Int
        var endMinute: Int
    }

    private static func extractWorkHours(from text: String) -> ParsedWorkHours? {
        let patterns: [String] = [
            #"(?i)(?:office|work(?:\s+hours)?|job|shift)\s*(?:is|:)?\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:–|-|to|until|through)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#,
            #"(?i)(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:–|-|to)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#,
            #"(?i)\b(\d{1,2})\s*(?:am|pm)?\s*(?:–|-)\s*(\d{1,2})\s*(?:am|pm)?\b"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                if pattern.contains("office") || pattern.contains("work") {
                    if let parsed = parseWorkHourMatch(text: text, match: match, groups: 6) {
                        return parsed
                    }
                } else if let parsed = parseSimpleRangeMatch(text: text, match: match) {
                    return parsed
                }
            }
        }

        // Classic "9-5" / "9 to 5"
        if let regex = try? NSRegularExpression(pattern: #"(?i)\b(\d{1,2})\s*(?:to|-)\s*(\d{1,2})\b"#),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let start = intGroup(match, 1, in: text),
           let end = intGroup(match, 2, in: text),
           (5...12).contains(start), (3...12).contains(end) {
            let endHour = end < start ? end + 12 : end
            return ParsedWorkHours(startHour: start, startMinute: 0, endHour: endHour, endMinute: 0)
        }

        return nil
    }

    private static func parseWorkHourMatch(text: String, match: NSTextCheckingResult, groups: Int) -> ParsedWorkHours? {
        guard let startH = intGroup(match, 1, in: text),
              let endH = intGroup(match, 4, in: text) else { return nil }
        let startM = intGroup(match, 2, in: text) ?? 0
        let endM = intGroup(match, 5, in: text) ?? 0
        let startMeridiem = stringGroup(match, 3, in: text)
        let endMeridiem = stringGroup(match, 6, in: text)
        guard let start = normalizeTime(hour: startH, minute: startM, meridiem: startMeridiem),
              let end = normalizeTime(hour: endH, minute: endM, meridiem: endMeridiem) else { return nil }
        let adjusted = adjustEndIfNeeded(start: start, end: end, startMeridiem: startMeridiem, endMeridiem: endMeridiem)
        return ParsedWorkHours(startHour: start.hour, startMinute: start.minute, endHour: adjusted.hour, endMinute: adjusted.minute)
    }

    private static func parseSimpleRangeMatch(text: String, match: NSTextCheckingResult) -> ParsedWorkHours? {
        guard let startH = intGroup(match, 1, in: text),
              let endH = intGroup(match, 4, in: text) else { return nil }
        let startM = intGroup(match, 2, in: text) ?? 0
        let endM = intGroup(match, 5, in: text) ?? 0
        let startMeridiem = stringGroup(match, 3, in: text)
        let endMeridiem = stringGroup(match, 6, in: text)
        guard let start = normalizeTime(hour: startH, minute: startM, meridiem: startMeridiem),
              let end = normalizeTime(hour: endH, minute: endM, meridiem: endMeridiem) else { return nil }
        let adjusted = adjustEndIfNeeded(start: start, end: end, startMeridiem: startMeridiem, endMeridiem: endMeridiem)
        return ParsedWorkHours(startHour: start.hour, startMinute: start.minute, endHour: adjusted.hour, endMinute: adjusted.minute)
    }

    private static func adjustEndIfNeeded(
        start: (hour: Int, minute: Int),
        end: (hour: Int, minute: Int),
        startMeridiem: String?,
        endMeridiem: String?
    ) -> (hour: Int, minute: Int) {
        guard startMeridiem == nil, endMeridiem == nil else { return end }
        let startMinutes = start.hour * 60 + start.minute
        let endMinutes = end.hour * 60 + end.minute
        if endMinutes <= startMinutes, end.hour <= 12 {
            return (end.hour + 12, end.minute)
        }
        return end
    }

    private static func normalizeTime(hour: Int, minute: Int, meridiem: String?) -> (hour: Int, minute: Int)? {
        var h = hour
        let m = min(max(minute, 0), 59)
        if let meridiem {
            let lower = meridiem.lowercased()
            if lower == "pm", h < 12 { h += 12 }
            if lower == "am", h == 12 { h = 0 }
        } else if h <= 8 && h >= 1 {
            // Bare numbers like 9-6 in work context → assume end is PM
        } else if h >= 1 && h <= 11 {
            // no meridiem on start hour only — keep as-is
        }
        guard (0...23).contains(h) else { return nil }
        return (h, m)
    }

    // MARK: - Fixed commitments

    private static func extractFixedCommitments(from text: String) -> [String] {
        var results: [String] = []
        let patterns = [
            #"(?i)(?:daily\s+)?stand[- ]?up(?:\s+at|\s*/)?\s*(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)"#,
            #"(?i)(\d{1,2}(?::\d{2})?\s*(?:am|pm))\s*[–-]?\s*(?:daily\s+)?stand[- ]?up"#,
            #"(?i)(?:school|kids?)\s+pickup(?:\s+at)?\s*(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)"#,
            #"(?i)(?:gym|workout|exercise)(?:\s+at|\s+@)?\s*(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)"#,
            #"(?i)\bmeeting\b(?:\s+at)?\s*(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)"#,
            #"(?i)\bcall\b(?:\s+at)?\s*(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)"#,
            #"(?i)\bclass\b(?:\s+at)?\s*(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)"#
        ]
        let labels = ["Daily standup", "Daily standup", "School pickup", "Gym", "Meeting", "Call", "Class"]

        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match, let time = stringGroup(match, 1, in: text) else { return }
                results.append("\(labels[index]) \(time.trimmingCharacters(in: .whitespaces))")
            }
        }
        return Array(Set(results)).sorted()
    }

    // MARK: - Helpers

    private static func intGroup(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> Int? {
        guard match.numberOfRanges > index,
              let range = Range(match.range(at: index), in: text) else { return nil }
        let raw = String(text[range]).trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        return Int(raw)
    }

    private static func stringGroup(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        guard match.numberOfRanges > index,
              let range = Range(match.range(at: index), in: text) else { return nil }
        let raw = String(text[range]).trimmingCharacters(in: .whitespaces)
        return raw.isEmpty ? nil : raw
    }
}
