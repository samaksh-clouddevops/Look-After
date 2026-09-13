import Foundation
import LookAfterCore

/// Sanitizes AI natural-language task extraction output before it reaches the review UI.
///
/// Mirrors `DayScheduleSuggestionValidator`'s role: repairs per-field *invalid* values
/// (e.g. negative minutes) but never repairs `ambiguous`/`unknown` fields by inventing a
/// value — those statuses are passed through so the review UI can prompt the user instead.
public enum NaturalLanguageTaskDraftValidator {
    private static let lowUrgencyKeywords = ["whenever", "no rush", "no hurry", "someday", "eventually"]
    private static let tomorrowKeywords = ["tomorrow"]

    public static func validated(_ draft: NaturalLanguageTaskDraft, now: Date = Date()) -> NaturalLanguageTaskDraft {
        var result = draft
        result.estimatedMinutes = repairedMinutes(draft.estimatedMinutes)

        var flags: [String] = []

        if let rawMinutes = draft.estimatedMinutes.value,
           MultiDaySuggestion.suggest(forRawMinutes: rawMinutes) != nil {
            flags.append("duration-exceeds-single-task")
        }

        if let scheduledAt = result.scheduledAt.value, let deadline = result.deadline.value,
           scheduledAt > deadline {
            flags.append("scheduledAt-after-deadline")
        }

        if let scheduledAt = result.scheduledAt.value, scheduledAt < now {
            flags.append("scheduledAt-in-past")
        }

        let lowerTitle = draft.title.lowercased()
        if let priority = result.priority.value, priority >= .high,
           lowUrgencyKeywords.contains(where: { lowerTitle.contains($0) }) {
            flags.append("priority-urgency-mismatch")
        }

        if tomorrowKeywords.contains(where: { lowerTitle.contains($0) }),
           let scheduledAt = result.scheduledAt.value,
           let calendarDay = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: now)),
           scheduledAt >= calendarDay {
            flags.append("deadline-scheduledAt-mismatch")
        }

        result.flaggedInconsistencies = flags
        return result
    }

    /// Clamps an out-of-range but present minutes value; does not fabricate one from "unknown".
    /// Values above the single-task ceiling are preserved so multi-day suggestion flags stay truthful.
    private static func repairedMinutes(_ field: ExtractedField<Int>) -> ExtractedField<Int> {
        guard let minutes = field.value, field.status == .known || field.status == .inferred else {
            return field
        }
        var repaired = field
        if minutes > TaskDurationPolicy.maximumMinutes {
            repaired.value = max(minutes, TaskDurationPolicy.minimumMinutes)
            return repaired
        }
        repaired.value = TaskDurationPolicy.clamp(minutes, allowShortTasks: true)
        return repaired
    }
}
