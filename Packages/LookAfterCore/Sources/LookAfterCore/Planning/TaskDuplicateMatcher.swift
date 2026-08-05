import Foundation

/// Conservative duplicate detection — avoids false positives on partial word overlap.
public enum TaskDuplicateMatcher {
    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "from", "that", "this", "your", "have", "need",
        "task", "work", "call", "make", "take", "finish", "start", "today", "also",
        "about", "just", "will", "want", "create", "add", "new"
    ]

    public static func findMatch(for title: String, in tasks: [LifeTask]) -> LifeTask? {
        let needle = normalize(title)
        guard !needle.isEmpty else { return nil }

        for task in tasks where isStrongMatch(needle: title, hay: task.title) {
            return task
        }
        return nil
    }

    public static func findMatches(for message: String, in tasks: [LifeTask]) -> [LifeTask] {
        let phrases = extractCandidateTitles(from: message)
        if phrases.isEmpty {
            return []
        }
        var seen = Set<String>()
        var matches: [LifeTask] = []
        for phrase in phrases {
            if let match = findMatch(for: phrase, in: tasks), !seen.contains(match.id) {
                seen.insert(match.id)
                matches.append(match)
            }
        }
        return matches
    }

    public static func isStrongMatch(needle: String, hay: String) -> Bool {
        let n = normalize(needle)
        let h = normalize(hay)
        guard !n.isEmpty, !h.isEmpty else { return false }
        if n == h { return true }

        let nTokens = significantTokens(needle)
        let hTokens = significantTokens(hay)
        guard !nTokens.isEmpty, !hTokens.isEmpty else { return false }

        if nTokens.count == 1, let token = nTokens.first {
            return hTokens.contains(token) && token.count >= 6
        }

        guard nTokens.count >= 2 else { return false }

        let overlap = nTokens.filter { hTokens.contains($0) }.count
        let ratio = Double(overlap) / Double(nTokens.count)
        return ratio >= 0.8
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func significantTokens(_ value: String) -> [String] {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }

    private static func extractCandidateTitles(from message: String) -> [String] {
        var text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            "create a task for ", "add a task for ", "create task for ", "add task for ",
            "schedule ", "remind me to ", "i need to ", "today i need to "
        ]
        var lowered = text.lowercased()
        for prefix in prefixes where lowered.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            lowered = text.lowercased()
        }
        if text.count >= 4 {
            return [text]
        }
        return []
    }
}
