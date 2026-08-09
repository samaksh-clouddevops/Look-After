import Foundation

/// Groups related captures via graph edges and title similarity.
public enum CaptureClusterAnalyzer {
    public struct Cluster: Sendable, Equatable {
        public var label: String
        public var inboxIDs: [String]
        public var estimatedMinutes: Int

        public init(label: String, inboxIDs: [String], estimatedMinutes: Int) {
            self.label = label
            self.inboxIDs = inboxIDs
            self.estimatedMinutes = estimatedMinutes
        }
    }

    public static func analyze(
        inboxItems: [InboxItem],
        edges: [CaptureGraphEdge],
        now: Date = Date(),
        staleHours: Int = 48
    ) -> [ProactiveAction] {
        let cutoff = now.addingTimeInterval(-TimeInterval(staleHours * 3600))
        let stale = inboxItems.filter {
            ($0.status == .unprocessed || $0.status == .needsReview) && $0.createdAt < cutoff
        }
        guard stale.count >= 2 else { return [] }

        var clusters: [Cluster] = []
        var consumed = Set<String>()

        for item in stale {
            guard !consumed.contains(item.id) else { continue }
            let linked = edges.filter { $0.sourceInboxID == item.id }.map(\.targetEntityID)
            var group = stale.filter { candidate in
                candidate.id == item.id
                    || linked.contains(where: { link in candidate.content.localizedCaseInsensitiveContains(link) })
                    || titleOverlap(item.content, candidate.content) >= 0.35
            }
            group = Array(Set(group.map(\.id))).compactMap { id in stale.first { $0.id == id } }
            guard group.count >= 2 else { continue }
            group.forEach { consumed.insert($0.id) }
            let label = clusterLabel(from: group)
            clusters.append(Cluster(label: label, inboxIDs: group.map(\.id), estimatedMinutes: min(30, group.count * 7)))
        }

        return clusters.prefix(2).map { cluster in
            ProactiveAction(
                kind: .captureResurrection,
                severity: .medium,
                message: "\(cluster.inboxIDs.count) related captures about \(cluster.label) — batch \(cluster.estimatedMinutes) min?",
                options: ["Batch schedule", "Review captures", "Snooze"],
                surface: .banner,
                relatedInboxIDs: cluster.inboxIDs,
                metadata: ["clusterLabel": cluster.label]
            )
        }
    }

    private static func clusterLabel(from items: [InboxItem]) -> String {
        let words = items.flatMap { $0.content.lowercased().split(whereSeparator: { !$0.isLetter }) }
        let counts = Dictionary(grouping: words.filter { $0.count > 3 }, by: { $0 }).mapValues(\.count)
        if let top = counts.max(by: { $0.value < $1.value })?.key {
            return String(top)
        }
        return String(items.first?.content.prefix(24) ?? "this topic")
    }

    private static func titleOverlap(_ a: String, _ b: String) -> Double {
        let setA = Set(a.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        let setB = Set(b.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        guard !setA.isEmpty, !setB.isEmpty else { return 0 }
        return Double(setA.intersection(setB).count) / Double(setA.union(setB).count)
    }
}
