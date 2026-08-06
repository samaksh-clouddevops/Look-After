import Foundation

/// Transforms LLM / markdown text into clean, natural spoken English.
public enum SpeechTextPreprocessor {

    /// Full pipeline: strip formatting, expand abbreviations, normalize lists → prose.
    public static func prepareForSpeech(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "" }

        result = stripCodeFences(result)
        result = stripMarkdown(result)
        result = normalizeLists(result)
        result = expandAbbreviations(result)
        result = collapseWhitespace(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Markdown

    public static func stripMarkdown(_ text: String) -> String {
        var s = text
        // Images ![alt](url) → alt
        s = replace(s, pattern: #"!\[([^\]]*)\]\([^)]+\)"#, template: "$1")
        // Links [label](url) → label
        s = replace(s, pattern: #"\[([^\]]+)\]\([^)]+\)"#, template: "$1")
        // Bold / italic markers
        s = replace(s, pattern: #"(\*\*|__)(.*?)\1"#, template: "$2")
        s = replace(s, pattern: #"(\*|_)(.*?)\1"#, template: "$2")
        // Inline code
        s = replace(s, pattern: #"`([^`]+)`"#, template: "$1")
        // Headers
        s = replace(s, pattern: #"(?m)^#{1,6}\s*"#, template: "")
        // Blockquotes
        s = replace(s, pattern: #"(?m)^>\s?"#, template: "")
        // Horizontal rules
        s = replace(s, pattern: #"(?m)^(-{3,}|\*{3,}|_{3,})\s*$"#, template: "")
        // Stray emphasis leftovers
        s = s.replacingOccurrences(of: "**", with: "")
        s = s.replacingOccurrences(of: "__", with: "")
        s = s.replacingOccurrences(of: "*", with: "")
        s = s.replacingOccurrences(of: "`", with: "")
        return s
    }

    public static func stripCodeFences(_ text: String) -> String {
        replace(text, pattern: #"```[\s\S]*?```"#, template: "")
    }

    // MARK: - Lists → prose

    /// Converts bullet / numbered lines into short spoken sentences.
    public static func normalizeLists(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var out: [String] = []
        var listBuffer: [String] = []

        func flushList() {
            guard !listBuffer.isEmpty else { return }
            if listBuffer.count == 1 {
                out.append(ensureSentence(listBuffer[0]))
            } else if listBuffer.count == 2 {
                out.append("\(ensureClause(listBuffer[0])), and \(ensureClause(listBuffer[1])).")
            } else {
                let head = listBuffer.dropLast().map(ensureClause).joined(separator: ", ")
                let last = ensureClause(listBuffer.last ?? "")
                out.append("\(head), and \(last).")
            }
            listBuffer.removeAll()
        }

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushList()
                continue
            }
            if let item = listItem(from: line) {
                listBuffer.append(item)
            } else {
                flushList()
                out.append(line)
            }
        }
        flushList()
        return out.joined(separator: " ")
    }

    // MARK: - Expansions

    public static func expandAbbreviations(_ text: String) -> String {
        var s = text
        // Ordered longest-first to avoid partial collisions.
        let rules: [(String, String)] = [
            (#"(?i)\bapprox\."#, "approximately"),
            (#"(?i)\bapprox\b"#, "approximately"),
            (#"(?i)\bhrs?\b"#, "hours"),
            (#"(?i)\bmins?\b"#, "minutes"),
            (#"(?i)\bsecs?\b"#, "seconds"),
            (#"(?i)\bw/\b"#, "with"),
            (#"(?i)\bw/o\b"#, "without"),
            (#"(?i)\be\.g\."#, "for example"),
            (#"(?i)\bi\.e\."#, "that is"),
            (#"(?i)\betc\."#, "and so on"),
            (#"(?i)\bvs\."#, "versus"),
            (#"(?i)\bvs\b"#, "versus"),
            (#"\bPPL\b"#, "Push-Pull-Legs"),
            (#"\bADHD\b"#, "A.D.H.D."),
            (#"\bAI\b"#, "A.I."),
            (#"\bETA\b"#, "E.T.A."),
            (#"\bFAQ\b"#, "F.A.Q."),
            (#"(?i)\bok\b"#, "okay"),
        ]
        for (pattern, replacement) in rules {
            s = replace(s, pattern: pattern, template: replacement)
        }
        // Time like 10:00 → 10 o'clock-ish spoken via Apple TTS is fine; expand "am/pm".
        s = replace(s, pattern: #"\b(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?)\b"#, template: "$1$2 A.M.", options: [.caseInsensitive])
        s = replace(s, pattern: #"\b(\d{1,2})(?::(\d{2}))?\s*(p\.?m\.?)\b"#, template: "$1$2 P.M.", options: [.caseInsensitive])
        return s
    }

    // MARK: - Helpers

    private static func listItem(from line: String) -> String? {
        // "- item", "* item", "• item", "1. item", "1) item"
        let patterns = [
            #"^[-*•]\s+(.+)$"#,
            #"^\d+[.)]\s+(.+)$"#,
        ]
        for pattern in patterns {
            if let match = firstMatch(line, pattern: pattern) {
                return match
            }
        }
        return nil
    }

    private static func ensureSentence(_ clause: String) -> String {
        let t = clause.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }
        if let last = t.last, ".!?".contains(last) { return t }
        return t + "."
    }

    private static func ensureClause(_ clause: String) -> String {
        var t = clause.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = t.last, ".!;,".contains(last) {
            t = String(t.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return t
    }

    private static func collapseWhitespace(_ text: String) -> String {
        replace(text, pattern: #"\s+"#, template: " ")
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
    }

    private static func replace(
        _ text: String,
        pattern: String,
        template: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private static func firstMatch(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
