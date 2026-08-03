import Foundation

public struct MultiDayDetectionResult: Sendable, Equatable {
    public var isMultiDay: Bool
    public var suggestedDayCount: Int?
    public var inferredLifeArea: LifeArea?
    public var titleHint: String?

    public init(
        isMultiDay: Bool = false,
        suggestedDayCount: Int? = nil,
        inferredLifeArea: LifeArea? = nil,
        titleHint: String? = nil
    ) {
        self.isMultiDay = isMultiDay
        self.suggestedDayCount = suggestedDayCount
        self.inferredLifeArea = inferredLifeArea
        self.titleHint = titleHint
    }
}

/// Heuristic detector for work that spans more than one day — used before LLM conversation.
public enum MultiDayTaskDetector {
    private static let spreadPhrases = [
        "over several days",
        "over multiple days",
        "across the week",
        "spread over",
        "spread across",
        "break into daily",
        "daily steps",
        "each day for",
        "every day for",
        "for the next",
        "multi-day",
        "multi day"
    ]

    public static func detect(in message: String) -> MultiDayDetectionResult {
        let lower = message.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return MultiDayDetectionResult() }

        let explicitDays = extractDayCount(from: lower)
        let mentionsSpread = spreadPhrases.contains(where: { lower.contains($0) })
            || (lower.contains("over") && lower.contains("day"))
            || (lower.contains("across") && (lower.contains("week") || lower.contains("days")))
            || lower.contains("plan something over")

        let isMultiDay = mentionsSpread || explicitDays != nil && (explicitDays ?? 0) >= 2

        guard isMultiDay else { return MultiDayDetectionResult() }

        return MultiDayDetectionResult(
            isMultiDay: true,
            suggestedDayCount: explicitDays ?? defaultDayCount(from: lower),
            inferredLifeArea: inferLifeArea(from: lower),
            titleHint: extractTitleHint(from: message)
        )
    }

    public static func extractDayCount(from text: String) -> Int? {
        let patterns: [String] = [
            #"(\d+)\s*[- ]?\s*day"#,
            #"for\s+(\d+)\s+days"#,
            #"next\s+(\d+)\s+days"#,
            #"(\d+)\s+day\s+plan"#
        ]
        for pattern in patterns {
            if let match = text.range(of: pattern, options: .regularExpression) {
                let snippet = String(text[match])
                if let digits = snippet.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap({ Int($0) }).first,
                   digits >= 2, digits <= 90 {
                    return digits
                }
            }
        }

        if text.contains("a week") || text.contains("one week") { return 5 }
        if text.contains("two weeks") { return 10 }
        if text.contains("this week") && !text.contains("today") { return 5 }

        return nil
    }

    private static func defaultDayCount(from text: String) -> Int {
        if text.contains("week") { return 5 }
        return 3
    }

    private static func inferLifeArea(from text: String) -> LifeArea? {
        if text.contains("gym") || text.contains("workout") || text.contains("exercise") { return .health }
        if text.contains("music") || text.contains("song") || text.contains("creative") { return .creativity }
        if text.contains("office") || text.contains("report") || text.contains("presentation") { return .work }
        if text.contains("learn") || text.contains("study") || text.contains("course") { return .learning }
        return nil
    }

    private static func extractTitleHint(from message: String) -> String? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["i need to ", "i want to ", "help me ", "plan "]
        var working = trimmed
        for prefix in prefixes where working.lowercased().hasPrefix(prefix) {
            working = String(working.dropFirst(prefix.count))
        }
        working = working.trimmingCharacters(in: .whitespacesAndNewlines)
        return working.count >= 4 ? working.prefix(80).description : nil
    }
}
