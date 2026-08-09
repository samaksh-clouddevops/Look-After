import Foundation

/// Follows up on stale inbox captures (working-memory prosthesis).
public enum CaptureResurrectionAnalyzer {
    public static func analyze(
        inboxItems: [InboxItem],
        memoryEntries: [MemoryEntry] = [],
        now: Date = Date(),
        staleHours: Int = 48
    ) -> [ProactiveAction] {
        let cutoff = now.addingTimeInterval(-TimeInterval(staleHours * 3600))
        var actions: [ProactiveAction] = []

        let staleInbox = inboxItems.filter { item in
            item.status == .unprocessed || item.status == .needsReview
        }.filter { $0.createdAt < cutoff }

        for item in staleInbox.prefix(2) {
            let snippet = String(item.content.prefix(60))
            actions.append(ProactiveAction(
                kind: .captureResurrection,
                severity: .medium,
                message: "You captured \"\(snippet)\" a few days ago — still relevant?",
                options: ["Schedule it", "Snooze", "Dismiss"],
                surface: .banner,
                relatedInboxIDs: [item.id]
            ))
        }

        let staleMemory = memoryEntries.filter { entry in
            entry.createdAt < cutoff && entry.importance >= 0.5
        }
        for entry in staleMemory.prefix(1) where actions.count < 3 {
            actions.append(ProactiveAction(
                kind: .captureResurrection,
                severity: .low,
                message: "Still thinking about \"\(entry.summary.isEmpty ? String(entry.content.prefix(40)) : entry.summary)\"?",
                options: ["Create task", "Snooze", "Archive"],
                surface: .planning,
                relatedInboxIDs: [entry.id]
            ))
        }

        return actions
    }
}
