import Foundation

public struct CalendarChangeResult: Sendable, Equatable {
    public var newEvents: [LifeTimelineEvent]
    public var changedEvents: [LifeTimelineEvent]
    public var summaryLine: String

    public init(newEvents: [LifeTimelineEvent], changedEvents: [LifeTimelineEvent], summaryLine: String) {
        self.newEvents = newEvents
        self.changedEvents = changedEvents
        self.summaryLine = summaryLine
    }
}

/// Detects new or moved calendar meetings on today's timeline.
public enum CalendarChangeDetector {
    private static let fingerprintKey = "proactive.calendar.fingerprint"

    public static func evaluate(
        timelineEvents: [LifeTimelineEvent],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> CalendarChangeResult? {
        let meetings = timelineEvents.filter { event in
            guard event.kind == .meeting || event.id.hasPrefix("cal-") || event.id.hasPrefix("event-") else { return false }
            return event.date > now && calendar.isDate(event.date, inSameDayAs: now)
        }

        let fingerprint = meetings.map { "\($0.id)|\($0.title)|\(Int($0.date.timeIntervalSince1970))" }.sorted().joined(separator: ";")
        let previous = UserDefaults.standard.string(forKey: fingerprintKey) ?? ""

        defer {
            UserDefaults.standard.set(fingerprint, forKey: fingerprintKey)
        }

        guard !previous.isEmpty, fingerprint != previous else { return nil }

        let previousParts = Set(previous.split(separator: ";").map(String.init))
        let currentParts = Set(fingerprint.split(separator: ";").map(String.init))
        let addedKeys = currentParts.subtracting(previousParts)
        guard !addedKeys.isEmpty else { return nil }

        let added = meetings.filter { event in
            let key = "\(event.id)|\(event.title)|\(Int(event.date.timeIntervalSince1970))"
            return addedKeys.contains(key)
        }

        guard !added.isEmpty else { return nil }

        let title = added.first?.title ?? "Meeting"
        let timeLabel = ScheduleTimeFormatting.timeLabel(added.first?.date ?? now, calendar: calendar)
        return CalendarChangeResult(
            newEvents: added,
            changedEvents: [],
            summaryLine: "New meeting \"\(title)\" at \(timeLabel) — adjust your plan?"
        )
    }

    public static func resetFingerprint() {
        UserDefaults.standard.removeObject(forKey: fingerprintKey)
    }
}
