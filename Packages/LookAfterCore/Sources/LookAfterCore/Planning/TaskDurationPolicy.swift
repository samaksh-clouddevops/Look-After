import Foundation

/// Resolves task durations while respecting explicit user-stated times.
public enum TaskDurationPolicy {
    public static let minimumMinutes = 1
    public static let defaultMinutes = 30
    public static let softDefaultMinutes = 5
    /// Upper bound for a true micro-start session when the task estimate is longer.
    public static let microStartCapMinutes = 5

    /// Session length for a micro-start — never invents a shorter number than a small estimate.
    public static func microStartSessionMinutes(for task: LifeTask) -> Int {
        let estimated = max(task.estimatedMinutes, minimumMinutes)
        return clamp(min(estimated, microStartCapMinutes), allowShortTasks: true)
    }

    /// User-facing duration phrase aligned with the task estimate (trust-safe).
    public static func microStartDurationPhrase(for task: LifeTask) -> String {
        let estimated = max(task.estimatedMinutes, minimumMinutes)
        let session = microStartSessionMinutes(for: task)
        if session < estimated {
            return "up to \(estimated) minutes"
        }
        return "\(estimated) minutes"
    }

    public static func microStartOptionLabel(for task: LifeTask) -> String {
        "Start \(microStartSessionMinutes(for: task))-min focus"
    }

    public static func microStartShortOptionLabel(minutes: Int = softDefaultMinutes) -> String {
        "Start \(clamp(minutes, allowShortTasks: true))-min"
    }

    /// Parses explicit durations like "1 min", "2 minutes", "5m".
    public static func parseExplicitMinutes(from text: String) -> Int? {
        let pattern = #"(\d+)\s*(?:min(?:ute)?s?|m)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text),
              let value = Int(text[valueRange]) else {
            return nil
        }
        return clamp(value, allowShortTasks: true)
    }

    public static func resolve(
        aiMinutes: Int?,
        userMessage: String?,
        phrase: String? = nil,
        defaultMinutes: Int = TaskDurationPolicy.defaultMinutes
    ) -> Int {
        if let explicit = phrase.flatMap(parseExplicitMinutes(from:))
            ?? userMessage.flatMap(parseExplicitMinutes(from:)) {
            return explicit
        }
        if let aiMinutes {
            return clamp(aiMinutes)
        }
        return clamp(defaultMinutes)
    }

    public static func clamp(_ minutes: Int, allowShortTasks: Bool = true) -> Int {
        let floor = allowShortTasks ? minimumMinutes : softDefaultMinutes
        return min(max(minutes, floor), 240)
    }
}
