import Foundation

/// User-visible copy helpers — internal Brain/scheduling categories never surface here.
public enum UserFacingCopy {

    // MARK: - Product branding

    public static let productName = "Look After"

    public static var medicalDisclaimer: String {
        "\(productName) is not a medical device."
    }

    public static var medicalDisclaimerWithProvider: String {
        "\(productName) is not a medical device. For severe symptoms, consult a healthcare provider."
    }

    // MARK: - Section titles

    public static let todayTitle = "Today"
    public static let suggestedNextStepTitle = "Suggested next step"
    public static let openWindowsTitle = "Open windows"
    public static let headsUpTitle = "Heads up"
    public static let progressTitle = "Progress"
    public static let chatTitle = "Ask anything"
    public static let bestWindowTitle = "Best window"
    public static let taskTimeTitle = "Time on tasks"
    public static let dayScoreTitle = "Day score"
    public static let healthSnapshotTitle = "Health snapshot"
    public static let noFocusWindowToday = FocusWindowFormatter.noStrongWindow
    public static let voiceCapturePlaceholder = "Tell me anything — I'll figure out where it belongs."
    public static let chooseForMeLabel = "Choose for me"
    public static let suggestAnotherPlanLabel = "Suggest another plan"

    // MARK: - Readiness labels

    /// Human-readable label for executive function / readiness score (0–100).
    public static func readinessLabel(score: Int) -> String {
        switch score {
        case 80...: return "Ready for focused work"
        case 65..<80: return "Good capacity today"
        case 50..<65: return "Steady — pace yourself"
        case 35..<50: return "Recovery mode"
        default: return "Take it easy today"
        }
    }

    /// Secondary band label shown beside the numeric score.
    public static func readinessBand(score: Int) -> String {
        switch score {
        case 80...: return "High"
        case 65..<80: return "Good"
        case 50..<65: return "Moderate"
        case 35..<50: return "Low"
        default: return "Rest"
        }
    }

    public static func recoveryLabel(percent: Int) -> String {
        switch percent {
        case 75...: return "Strong"
        case 50..<75: return "Moderate"
        case 30..<50: return "Low"
        default: return "Depleted"
        }
    }

    // MARK: - Action labels

    public static func actionButtonLabel(for action: FlowActionType, task: LifeTask) -> String {
        HumanLanguage.outcomeHeadline(task: task)
    }

    public static func actionDurationSubtitle(minutes: Int) -> String {
        let label = HumanLanguage.durationLabel(minutes: minutes)
        if label.hasSuffix(" left") {
            return String(label.dropLast(5)) + "."
        }
        return label + "."
    }

    public static func microActionLabel(task: LifeTask) -> String {
        HumanLanguage.outcomeHeadline(task: task)
    }

    public static func microActionMessage(deferralCount: Int) -> String {
        "You've put this off \(deferralCount) times. Five minutes now?"
    }

    // MARK: - Focus windows

    public static func focusWindow(timeRange: String, detail: String) -> (label: String, detail: String) {
        (label: timeRange, detail: detail)
    }

    public static let defaultWindowDetail = "Usually your most uninterrupted stretch."
    public static let lowEnergyWindowDetail = "Try shorter blocks today."
    public static let workoutWindowDetail = "Often a good time to move."
    public static let creativeWindowDetail = "Good for lighter planning or ideas."
    public static let recoveryWindowDetail = "Wind down and protect sleep."

    // MARK: - Sanitization

    /// Internal execution mechanisms — must never appear in user-facing copy.
    private static let internalExecutionLabels: [String] = [
        "deep work block",
        "focus block",
        "smart work",
        "focus session",
        "uninterrupted time session",
        "uninterrupted time",
        "productivity mode",
        "planning block",
        "context window",
        "planning session",
        "work session",
        "execution block",
        "focus mode",
        "focus prediction",
        "executive recommendation",
        "flow director",
        "productivity score",
        "ef score",
        "ef index",
        "peak focus window",
        "optimal next step",
    ]

    private static let internalSectionLabels: [String] = [
        "executive recommendation",
        "today's mission",
        "ai coach",
        "smart alerts",
    ]

    /// Returns true when the entire label is an internal execution concept.
    public static func isInternalExecutionLabel(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }

        if internalExecutionLabels.contains(where: { normalized == $0 || normalized.hasPrefix($0 + " ") || normalized.hasSuffix(" " + $0) }) {
            return true
        }

        let patterns = [
            #"^deep work block\s*\d*$"#,
            #"^focus block\s*\d*$"#,
            #"^uninterrupted time(\s+session)?$"#,
            #"^focus session\s*\d*$"#,
            #"^planning block\s*\d*$"#,
            #"^session\s*\d*$"#,
            #"^context window\s*\d*$"#,
            #"^productivity mode$"#,
        ]
        for pattern in patterns {
            if normalized.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }

        return internalExecutionLabels.contains { normalized.contains($0) }
            && !containsConcreteObjective(in: normalized)
    }

    /// Strips internal labels; never substitutes another internal term.
    public static func sanitize(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        for phrase in internalExecutionLabels + internalSectionLabels {
            result = replaceCaseInsensitive(phrase, with: "", in: result)
        }

        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if isInternalExecutionLabel(result) { return "" }
        return result
    }

    /// Re-resolve if rendered headline still exposes execution mechanics.
    public static func ensurePublicObjective(
        _ headline: String,
        rawObjective: String,
        context: HeroObjectiveContext
    ) -> String {
        let cleaned = sanitize(headline)
        if !cleaned.isEmpty, !isInternalExecutionLabel(cleaned) {
            return cleaned
        }

        let raw = sanitize(rawObjective)
        if !raw.isEmpty, !isInternalExecutionLabel(raw) {
            if context.progress > 0 {
                return "Continue \(raw)"
            }
            if raw.lowercased().hasPrefix("finish ") || raw.lowercased().hasPrefix("review ")
                || raw.lowercased().hasPrefix("reply ") || raw.lowercased().hasPrefix("pay ") {
                return raw
            }
            return "Finish \(raw)"
        }

        let alternate = HeroObjectiveResolver.resolveRawObjective(from: context)
        if !alternate.isEmpty, alternate != rawObjective, !isInternalExecutionLabel(alternate) {
            if context.progress > 0 { return "Continue \(alternate)" }
            return "Finish \(alternate)"
        }

        return HumanLanguage.render(.pickUp).headline
    }

    public static func containsInternalCategory(_ text: String) -> Bool {
        isInternalExecutionLabel(text) || internalSectionLabels.contains { text.lowercased().contains($0) }
    }

    public static func isGenericMotivation(_ text: String) -> Bool {
        let lowered = sanitize(text).lowercased()
        if lowered.isEmpty { return true }
        if isInternalExecutionLabel(text) { return true }
        return lowered.contains("deep breath")
            || lowered.contains("feels easiest")
            || lowered.contains("💙")
    }

    private static func containsConcreteObjective(in normalized: String) -> Bool {
        let concreteMarkers = [
            "apple health", "healthkit", "azure", "deployment", "guitar", "electricity",
            "bill", "reply", "email", "review", "implement", "connect", "practice", "plan tomorrow",
        ]
        return concreteMarkers.contains { normalized.contains($0) }
    }

    private static func replaceCaseInsensitive(_ target: String, with replacement: String, in source: String) -> String {
        guard !target.isEmpty else { return source }
        var result = source
        var searchRange = result.startIndex..<result.endIndex
        while let range = result.range(of: target, options: .caseInsensitive, range: searchRange) {
            result.replaceSubrange(range, with: replacement)
            searchRange = range.lowerBound..<result.endIndex
        }
        return result
    }
}
