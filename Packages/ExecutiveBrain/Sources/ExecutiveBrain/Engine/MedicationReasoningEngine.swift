import Foundation
import LifeOSCore

/// Medication reasoning with strict safety rules.
///
/// The Brain NEVER invents dosing times. It only reflects the user's configured schedule
/// and logged adherence. It must never suggest "take this evening" for a morning medication
/// unless the user explicitly scheduled it for evening.
public enum MedicationReasoningEngine: Sendable {

    public static let prohibitedPhrases = [
        "take this evening",
        "take it tonight",
        "take before bed",
        "take at bedtime"
    ]

    public static func buildWorldStatus(
        medications: [Medication],
        now: Date,
        calendar: Calendar = .current
    ) -> MedicationWorldStatus {
        guard !medications.isEmpty else { return .noneConfigured }

        let todayItems = medications.map { med -> MedicationDueItem in
            let scheduledToday = scheduledTimeToday(med.scheduledTime, now: now, calendar: calendar)
            return MedicationDueItem(
                id: med.id,
                name: med.name,
                dosage: med.dosage,
                scheduledTimeLabel: scheduledToday.formatted(date: .omitted, time: .shortened),
                scheduledTime: scheduledToday,
                isTaken: med.isTaken
            )
        }

        if todayItems.allSatisfy(\.isTaken) {
            return .allTakenToday
        }

        let untaken = todayItems.filter { !$0.isTaken }
        let dueNow = untaken.filter { isInWindow(scheduled: $0.scheduledTime, now: now, calendar: calendar) }
        if !dueNow.isEmpty { return .dueNow(items: dueNow) }

        let missed = untaken.filter { isPastWindow(scheduled: $0.scheduledTime, now: now, calendar: calendar) }
        if !missed.isEmpty { return .missedToday(items: missed) }

        let upcoming = untaken.filter { !isPastWindow(scheduled: $0.scheduledTime, now: now, calendar: calendar) }
        if !upcoming.isEmpty { return .upcoming(items: upcoming) }

        return .allTakenToday
    }

    public static func reasoningFactors(for status: MedicationWorldStatus) -> [ReasoningFactor] {
        switch status {
        case .unknown, .noneConfigured:
            return []
        case .allTakenToday:
            return [
                ReasoningFactor(
                    domain: .medication,
                    observation: "Today's medications are logged.",
                    impact: .supports,
                    weight: 0.4
                )
            ]
        case .dueNow(let items):
            return items.map { item in
                ReasoningFactor(
                    domain: .medication,
                    observation: "\(item.name) is scheduled for \(item.scheduledTimeLabel) and hasn't been logged.",
                    impact: .constrains,
                    weight: 0.85
                )
            }
        case .missedToday(let items):
            return items.map { item in
                ReasoningFactor(
                    domain: .medication,
                    observation: "\(item.name) was scheduled for \(item.scheduledTimeLabel) and still isn't logged.",
                    impact: .constrains,
                    weight: 0.7
                )
            }
        case .upcoming(let items):
            return items.map { item in
                ReasoningFactor(
                    domain: .medication,
                    observation: "\(item.name) is scheduled for \(item.scheduledTimeLabel).",
                    impact: .neutral,
                    weight: 0.3
                )
            }
        }
    }

    /// Safe user-facing copy — schedule-bound only.
    public static func reminderMessage(for status: MedicationWorldStatus) -> String? {
        switch status {
        case .dueNow(let items):
            guard let first = items.first else { return nil }
            return "Log \(first.name) — scheduled for \(first.scheduledTimeLabel)."
        case .missedToday(let items):
            guard let first = items.first else { return nil }
            return "Today's \(first.name) dose (\(first.scheduledTimeLabel)) wasn't logged yet."
        default:
            return nil
        }
    }

    /// Rejects unsafe copy that invents medical advice or wrong timing.
    public static func isSafeRecommendation(_ text: String, status: MedicationWorldStatus) -> Bool {
        let lower = text.lowercased()
        for phrase in prohibitedPhrases {
            if lower.contains(phrase) { return false }
        }

        switch status {
        case .dueNow(let items), .missedToday(let items), .upcoming(let items):
            for item in items {
                if isMorningMedication(item), lower.contains("evening") || lower.contains("tonight") {
                    return false
                }
            }
        default:
            break
        }
        return true
    }

    // MARK: - Schedule helpers

    private static func scheduledTimeToday(_ scheduled: Date, now: Date, calendar: Calendar) -> Date {
        let time = calendar.dateComponents([.hour, .minute], from: scheduled)
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = time.hour
        components.minute = time.minute
        return calendar.date(from: components) ?? scheduled
    }

    private static func isInWindow(scheduled: Date, now: Date, calendar: Calendar) -> Bool {
        let start = scheduled.addingTimeInterval(-30 * 60)
        let end = scheduled.addingTimeInterval(60 * 60)
        return now >= start && now <= end
    }

    private static func isPastWindow(scheduled: Date, now: Date, calendar: Calendar) -> Bool {
        let end = scheduled.addingTimeInterval(60 * 60)
        return now > end
    }

    private static func isMorningMedication(_ item: MedicationDueItem) -> Bool {
        Calendar.current.component(.hour, from: item.scheduledTime) < 12
    }
}
