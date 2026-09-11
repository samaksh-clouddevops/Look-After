import Foundation

/// Present task titles in human language (avoid AI-looking em-dash suffixes).
public enum TaskTitleDisplay {
    /// Converts seeded / planner titles into natural labels for UI.
    public static func humanized(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let lower = trimmed.lowercased()
        if lower == "brush teeth — morning"
            || lower == "brush teeth – morning"
            || lower == "brush teeth - morning"
            || lower == "brush teeth (morning)" {
            return "Brush teeth after waking"
        }
        if lower == "brush teeth — evening"
            || lower == "brush teeth – evening"
            || lower == "brush teeth - evening"
            || lower == "brush teeth (evening)" {
            return "Brush teeth before bed"
        }
        if lower.hasPrefix("brush teeth") && lower.contains("catch-up") {
            return "Brush teeth (catch-up)"
        }

        // Generic "Title — qualifier" → "Title (qualifier)" for short suffixes.
        for separator in [" — ", " – ", " - "] {
            guard let range = trimmed.range(of: separator) else { continue }
            let head = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let tail = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !head.isEmpty, !tail.isEmpty, tail.count <= 24, !tail.contains(".") else { break }
            return "\(head) (\(tail))"
        }
        return trimmed
    }

    /// Stable key for routine dedupe (aliases share one key).
    public static func seriesKey(_ title: String) -> String {
        humanized(title)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
