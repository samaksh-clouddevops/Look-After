import Foundation
import LookAfterCore

/// Sanitizes AI schedule JSON before building a day plan preview.
public enum DayScheduleSuggestionValidator {
    public static func validated(
        _ suggestions: [DayScheduleSuggestion],
        allowedTaskIDs: Set<String>
    ) -> [DayScheduleSuggestion] {
        var seenTaskIDs = Set<String>()
        var seenTimeSlots = Set<String>()
        var result: [DayScheduleSuggestion] = []

        for suggestion in suggestions {
            guard allowedTaskIDs.contains(suggestion.id) else { continue }
            guard seenTaskIDs.insert(suggestion.id).inserted else { continue }

            let hour = min(max(suggestion.startHour, 0), 23)
            let minute = min(max(suggestion.startMinute, 0), 59)
            let slotKey = "\(hour):\(minute)"
            guard seenTimeSlots.insert(slotKey).inserted else { continue }

            result.append(
                DayScheduleSuggestion(
                    id: suggestion.id,
                    startHour: hour,
                    startMinute: minute,
                    reason: suggestion.reason
                )
            )
        }

        return result
    }
}
