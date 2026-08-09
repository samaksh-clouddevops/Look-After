import Foundation

/// Sunday evening / Monday morning week primer with top tasks.
public enum WeekPrimerDetector {
    public static func evaluate(
        tasks: [LifeTask],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ProactiveAction? {
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)
        let isSundayEvening = weekday == 1 && hour >= 18
        let isMondayMorning = weekday == 2 && hour >= 7 && hour <= 10
        guard isSundayEvening || isMondayMorning else { return nil }

        let top = tasks.filter(\.status.isActive).sorted { $0.priority > $1.priority }.prefix(3)
        guard !top.isEmpty else { return nil }

        let titles = top.map(\.title).joined(separator: ", ")
        let dayLabel = isSundayEvening ? "This week" : "Monday"
        return ProactiveAction(
            kind: .weekPrimer,
            severity: .medium,
            message: "\(dayLabel): top priorities — \(titles)",
            options: ["Open plan", "Preview week", "Not now"],
            surface: .notification,
            relatedTaskIDs: top.map(\.id),
            expiresAt: now.addingTimeInterval(3 * 3600)
        )
    }
}
