import Foundation
import LookAfterCore

/// Builds shame-free initiation scripts from task metadata and deferral count.
public enum InitiationScriptBuilder {

    public static func build(task: LifeTask, deferralCount: Int) -> InitiationScript {
        let duration = TaskDurationPolicy.microStartSessionMinutes(for: task)
        let durationPhrase = TaskDurationPolicy.microStartDurationPhrase(for: task)
        let firstStep = firstActionStep(for: task)
        let steps = [firstStep, "Set a timer for \(duration) minutes", "Stop when the timer ends — progress counts"]
        let message: String
        switch deferralCount {
        case 0...1:
            message = "Let's make \"\(task.title)\" tiny — \(durationPhrase) is enough to start."
        case 2...3:
            message = "You've postponed \"\(task.title)\" \(deferralCount) times. A micro-start (\(durationPhrase)) breaks the loop."
        default:
            message = "No judgment — \"\(task.title)\" has waited \(deferralCount) times. Try \(durationPhrase), then decide."
        }
        return InitiationScript(
            taskID: task.id,
            taskTitle: task.title,
            deferralCount: deferralCount,
            steps: steps,
            durationMinutes: duration,
            message: message
        )
    }

    private static func firstActionStep(for task: LifeTask) -> String {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.lowercased().hasPrefix("call ") {
            return "Open your phone and find the contact — don't dial yet"
        }
        if title.lowercased().contains("email") {
            return "Open the draft — write one sentence only"
        }
        if let verb = title.split(separator: " ").first {
            return "Just \(verb.lowercased()) — open whatever you need, don't finish"
        }
        return "Open what you need for \"\(title)\" — no finishing yet"
    }
}
