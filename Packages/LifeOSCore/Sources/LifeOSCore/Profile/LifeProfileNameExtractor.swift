import Foundation

/// Extracts a preferred first name from life-profile text (no AI required).
public enum LifeProfileNameExtractor {

    private static let blockedTokens: Set<String> = [
        "a", "an", "the", "very", "really", "currently", "working", "someone", "here",
        "not", "just", "also", "still", "trying", "looking", "based", "living", "always",
        "usually", "often", "someone", "person", "professional", "manager", "engineer",
        "student", "developer", "designer", "founder", "consultant", "freelancer"
    ]

    public static func extract(
        profileText: String,
        sections: StructuredLifeProfileSections? = nil
    ) -> String? {
        if let sections {
            for field in [sections.personality, sections.dailySchedule] {
                if let name = extract(from: field) { return name }
            }
        }
        return extract(from: profileText)
    }

    public static func extract(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let patterns = [
            #"(?i)(?:^|\n)\s*(?:my name is|i'?m|i am|call me|this is|name\s*[:\-])\s+([A-Za-z][A-Za-z'\-]{1,30})"#,
            #"(?i)(?:^|\n)\s*([A-Za-z][A-Za-z'\-]{2,20})\s+here\b"#,
            #"(?i)(?:^|\n)\s*hi[,!]?\s*(?:i'?m|i am)\s+([A-Za-z][A-Za-z'\-]{1,30})"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                  let range = Range(match.range(at: 1), in: trimmed) else { continue }
            if let name = sanitizeCandidate(String(trimmed[range])) { return name }
        }

        return nil
    }

    private static func sanitizeCandidate(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= 2, name.count <= 32 else { return nil }
        guard name.first?.isLetter == true else { return nil }

        let lower = name.lowercased()
        if blockedTokens.contains(lower) { return nil }
        if lower.hasPrefix("adhd") || lower.hasPrefix("pm ") { return nil }

        // Title-case single first name.
        return name.prefix(1).uppercased() + name.dropFirst().lowercased()
    }
}
