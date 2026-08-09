import Foundation

/// Surfaces long-horizon trends from cached analytics as proactive coaching.
public enum PatternCoachAnalyzer {
    public static func analyze(
        analytics: CachedAIContextSummary?,
        now: Date = Date()
    ) -> [ProactiveAction] {
        guard let analytics, !analytics.isStale else { return [] }
        var actions: [ProactiveAction] = []

        if analytics.sleepTrend == "declining", let average = analytics.sleepAverage, average < 7 {
            actions.append(ProactiveAction(
                kind: .patternCoach,
                severity: .medium,
                message: "Sleep's been short lately (~\(String(format: "%.1f", average))h) — want me to lighten today?",
                options: ["Lighten today", "Keep plan"],
                surface: .banner,
                metadata: ["signal": "sleep_declining"]
            ))
        }

        if let completion = analytics.weeklyTaskCompletion, completion < 40 {
            actions.append(ProactiveAction(
                kind: .patternCoach,
                severity: .medium,
                message: "Completion has dipped this week — defer a couple of lower-priority items?",
                options: ["Show defer options", "Keep plan"],
                surface: .planning,
                metadata: ["signal": "completion_low"]
            ))
        }

        if let peak = analytics.peakProductivityWindow, !peak.isEmpty {
            actions.append(ProactiveAction(
                kind: .patternCoach,
                severity: .low,
                message: "Your best window lately is \(peak) — protect it for deep work?",
                options: ["Protect window", "Not now"],
                surface: .banner,
                metadata: ["signal": "peak_window"]
            ))
        }

        return actions
    }
}
