import Foundation

public enum ProactiveFeedbackOutcome: String, Codable, Sendable {
    case accepted
    case dismissed
    case snoozed
}

public struct ProactiveFeedbackEvent: Codable, Sendable, Equatable {
    public var kind: String
    public var outcome: ProactiveFeedbackOutcome
    public var recordedAt: Date

    public init(kind: String, outcome: ProactiveFeedbackOutcome, recordedAt: Date = Date()) {
        self.kind = kind
        self.outcome = outcome
        self.recordedAt = recordedAt
    }
}

/// Tracks accept/dismiss/snooze per proactive kind for personalized ranking.
public enum ProactiveFeedbackStore {
    private static let storageKey = "lookafter.proactive.feedback"
    private static let maxEvents = 200
    private static let suppressThreshold = 3
    private static let boostThreshold = 2

    public static func record(
        kind: ProactiveAction.Kind,
        outcome: ProactiveFeedbackOutcome,
        now: Date = Date()
    ) {
        var events = loadEvents()
        events.append(ProactiveFeedbackEvent(kind: kind.rawValue, outcome: outcome, recordedAt: now))
        if events.count > maxEvents {
            events = Array(events.suffix(maxEvents))
        }
        saveEvents(events)
    }

    public static func score(for kind: ProactiveAction.Kind, now: Date = Date()) -> Int {
        let recent = loadEvents().filter { $0.kind == kind.rawValue && $0.recordedAt > now.addingTimeInterval(-14 * 86400) }
        let accepted = recent.filter { $0.outcome == .accepted }.count
        let dismissed = recent.filter { $0.outcome == .dismissed }.count
        let snoozed = recent.filter { $0.outcome == .snoozed }.count
        return accepted * 2 - dismissed * 3 - snoozed
    }

    public static func shouldSuppress(kind: ProactiveAction.Kind, now: Date = Date()) -> Bool {
        let recent = loadEvents().filter { $0.kind == kind.rawValue && $0.recordedAt > now.addingTimeInterval(-7 * 86400) }
        let dismissed = recent.filter { $0.outcome == .dismissed }.count
        let accepted = recent.filter { $0.outcome == .accepted }.count
        return dismissed >= suppressThreshold && accepted == 0
    }

    public static func boost(for kind: ProactiveAction.Kind, now: Date = Date()) -> Int {
        guard !shouldSuppress(kind: kind, now: now) else { return -10 }
        let s = score(for: kind, now: now)
        if s >= boostThreshold { return 3 }
        if s <= -boostThreshold { return -3 }
        return 0
    }

    public static func promptSummary(now: Date = Date()) -> String {
        let kinds = Set(loadEvents().map(\.kind))
        guard !kinds.isEmpty else { return "" }
        var lines: [String] = ["PROACTIVE PREFERENCES (last 14 days):"]
        for kindRaw in kinds.sorted() {
            guard let kind = ProactiveAction.Kind(rawValue: kindRaw) else { continue }
            let s = score(for: kind, now: now)
            if s != 0 {
                lines.append("- \(kindRaw): score \(s)")
            }
        }
        return lines.count > 1 ? lines.joined(separator: "\n") : ""
    }

    public static func resetForFactoryReset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private static func loadEvents() -> [ProactiveFeedbackEvent] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? SharedFormatters.jsonDecoderSeconds.decode([ProactiveFeedbackEvent].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func saveEvents(_ events: [ProactiveFeedbackEvent]) {
        if let data = try? SharedFormatters.jsonEncoderSeconds.encode(events) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
