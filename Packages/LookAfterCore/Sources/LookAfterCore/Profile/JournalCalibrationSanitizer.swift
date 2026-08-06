import Foundation

/// Normalizes LLM journal calibration output for display and storage.
public enum JournalCalibrationSanitizer {
    private static let preferredKeys = [
        "summary", "calibration", "calibrations", "text", "message", "insight", "insights",
        "content", "response", "result", "output", "analysis", "learning", "note", "feedback",
    ]

    public static func plainText(from raw: String) -> String {
        var text = stripFences(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !text.isEmpty else { return "" }

        if let jsonSlice = extractJSONPayload(from: text),
           let parsed = parseJSONToPlainText(jsonSlice) {
            return parsed
        }

        if (text.hasPrefix("{") || text.hasPrefix("[")),
           let parsed = parseJSONToPlainText(text) {
            return parsed
        }

        return stripJSONDebris(text)
    }

    // MARK: - JSON extraction

    private static func extractJSONPayload(from text: String) -> String? {
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
        let slice = String(text[start...])
        if let balanced = balancedJSONPrefix(in: slice) {
            return balanced
        }
        return slice
    }

    private static func balancedJSONPrefix(in text: String) -> String? {
        var depth = 0
        var inString = false
        var escaped = false
        let open: Character
        let close: Character
        guard let first = text.first, first == "{" || first == "[" else { return nil }
        open = first
        close = first == "{" ? "}" : "]"

        for (index, char) in text.enumerated() {
            if inString {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                }
                continue
            }

            if char == "\"" {
                inString = true
                continue
            }
            if char == open {
                depth += 1
            } else if char == close {
                depth -= 1
                if depth == 0 {
                    return String(text.prefix(index + 1))
                }
            }
        }
        return nil
    }

    private static func parseJSONToPlainText(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return flattenJSONObject(object)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func flattenJSONObject(_ object: Any) -> String? {
        if let string = object as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let array = object as? [Any] {
            let parts = array.compactMap { flattenJSONObject($0) }.filter { !$0.isEmpty }
            guard !parts.isEmpty else { return nil }
            return parts.joined(separator: " ")
        }

        if let dict = object as? [String: Any] {
            for key in preferredKeys {
                if let value = dict[key], let text = flattenJSONObject(value) {
                    return text
                }
            }
            let stringValues = dict.values.compactMap { flattenJSONObject($0) }.filter { $0.count >= 8 }
            if let best = stringValues.max(by: { $0.count < $1.count }) {
                return best
            }
        }

        return nil
    }

    // MARK: - Cleanup

    private static func stripFences(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "```json", with: "", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "```", with: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripJSONDebris(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: #"(?m)^[\{\}\[\],]+$"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #""[\w_]+"\s*:\s*"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: "{", with: "")
        result = result.replacingOccurrences(of: "}", with: "")
        result = result.replacingOccurrences(of: "[", with: "")
        result = result.replacingOccurrences(of: "]", with: "")
        result = result.replacingOccurrences(of: "\"", with: "")
        result = result.replacingOccurrences(of: "\\n", with: " ")
        return result
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
