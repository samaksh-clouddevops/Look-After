import Foundation
import LookAfterCore

/// Sunday predictive week shaping from Mon–Wed density + deferral trend.
public enum WeekShapeAnalyzer {
    public static func evaluate(
        timelineEvents: [LifeTimelineEvent],
        deferralCount: Int,
        tasks: [LifeTask],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ProactiveAction? {
        guard calendar.component(.weekday, from: now) == 1 else { return nil }
        guard calendar.component(.hour, from: now) >= 16 else { return nil }

        let monday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let wednesday = calendar.date(byAdding: .day, value: 3, to: monday) ?? now
        let denseBlocks = timelineEvents.filter { event in
            event.date >= monday && event.date <= wednesday && (event.kind == .meeting || event.isFixed)
        }.count

        let deferralNote = deferralCount >= 3 ? " You've deferred a lot lately." : ""
        let densityNote = denseBlocks >= 6 ? " Mon–Wed looks packed (\(denseBlocks) fixed blocks)." : " Mon–Wed has room."

        let top = tasks.filter(\.status.isActive).sorted { $0.priority > $1.priority }.prefix(3)
        let preview = top.map(\.title).joined(separator: ", ")

        return ProactiveAction(
            kind: .weekPrimer,
            severity: .medium,
            message: "\(densityNote)\(deferralNote) Top 3: \(preview)",
            options: ["Preview 3-day plan", "Open week", "Not now"],
            surface: .banner,
            relatedTaskIDs: top.map(\.id),
            metadata: ["denseBlocks": "\(denseBlocks)", "deferrals": "\(deferralCount)"]
        )
    }

    public static func threeDayVariant(tasks: [LifeTask]) -> PlanVariant? {
        let flexible = tasks.filter { $0.status.isActive && !$0.isFixedTimeEvent }
        let variants = PlanVariantBuilder.buildOfflineVariants(tasks: tasks, deferCandidates: Array(flexible.prefix(4)))
        return variants.first
    }
}
