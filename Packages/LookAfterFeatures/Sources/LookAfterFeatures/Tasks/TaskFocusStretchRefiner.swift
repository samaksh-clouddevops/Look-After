import Foundation
import LookAfterAI
import LookAfterCore

/// Optional LLM refinement when a task exceeds a single focus stretch.
struct TaskFocusStretchRefiner {

    func refine(
        task: LifeTask,
        context: TaskFocusStretchResolver.Context,
        estimatedMinutes: Int
    ) async -> TaskTimeDisplayInfo? {
        let hasKey = GLMService.shared.hasConfiguredAPIKey
        guard hasKey else { return nil }

        let baseline = TaskFocusStretchResolver.recommendedFocusStretch(for: task, context: context)
        let prompt = """
        Task: "\(task.title)"
        Total estimated time: \(estimatedMinutes) minutes
        Difficulty: \(task.difficulty.rawValue)
        Energy today: \(Int(context.energyScore * 100))%
        Executive capacity: \(context.executiveCapacity.band.displayLabel)
        Baseline focus stretch: \(baseline) minutes

        The user has ADHD. How many minutes can they realistically focus on THIS task at one stretch before needing a break?
        Reply with ONLY a JSON object: {"focusMinutes": <integer between 5 and 60>, "reason": "<one short human sentence, no jargon>"}
        """

        do {
            let raw = try await GLMService.shared.complete(
                prompt: prompt,
                systemPrompt: LookAfterPrompts.taskFocusStretchSystem,
                tier: .economy
            )
            guard let parsed = parseResponse(raw, fallbackMinutes: baseline) else { return nil }
            let label = "Focus for \(parsed.minutes) min at a stretch"
            return TaskTimeDisplayInfo(
                lineLabel: label,
                chipLabel: label,
                usesFocusStretch: true,
                focusStretchMinutes: parsed.minutes,
                needsAIRefinement: false
            )
        } catch {
            return nil
        }
    }

    private struct Parsed {
        var minutes: Int
        var reason: String
    }

    private func parseResponse(_ raw: String, fallbackMinutes: Int) -> Parsed? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonSlice: String
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            jsonSlice = String(trimmed[start...end])
        } else {
            jsonSlice = trimmed
        }
        guard let data = jsonSlice.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let minutes = object["focusMinutes"] as? Int else {
            return Parsed(minutes: fallbackMinutes, reason: "")
        }
        let reason = (object["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Parsed(minutes: TaskDurationPolicy.clamp(minutes), reason: reason)
    }
}
