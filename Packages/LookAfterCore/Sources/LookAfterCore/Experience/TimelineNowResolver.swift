import Foundation

/// Resolves the timeline NOW marker — shared by Today timeline UI and pin-to-lock-screen.
public enum TimelineNowResolver {

    /// Events sorted the same way as `TimelineRowProjector`.
    public static func sortedEvents(_ events: [LifeTimelineEvent]) -> [LifeTimelineEvent] {
        events.sorted(by: timelineEventSortOrder)
    }

    /// The event marked NOW on the Today timeline at `now`.
    public static func currentNowEvent(
        in events: [LifeTimelineEvent],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> LifeTimelineEvent? {
        let sorted = sortedEvents(events)
        guard let index = currentEventIndex(in: sorted, now: now, calendar: calendar) else { return nil }
        return sorted[index]
    }

    /// Index of the NOW event in a pre-sorted event list.
    public static func currentEventIndex(
        in events: [LifeTimelineEvent],
        now: Date,
        calendar: Calendar = .current
    ) -> Int? {
        for (index, event) in events.enumerated() {
            guard !event.isCompleted else { continue }
            let end = event.resolvedEndDate(calendar: calendar)
            if event.date <= now, now <= end { return index }
        }
        return events.firstIndex { !$0.isCompleted && $0.date > now }
    }

    public static func taskId(from eventId: String) -> String? {
        guard eventId.hasPrefix("task-") else { return nil }
        let id = String(eventId.dropFirst(5))
        return id.isEmpty ? nil : id
    }

    private static func timelineEventSortOrder(_ lhs: LifeTimelineEvent, _ rhs: LifeTimelineEvent) -> Bool {
        if lhs.id.hasPrefix("sleep-boundary") != rhs.id.hasPrefix("sleep-boundary") {
            return !lhs.id.hasPrefix("sleep-boundary")
        }
        if lhs.isFlexibleToday != rhs.isFlexibleToday {
            return !lhs.isFlexibleToday
        }
        if lhs.isFlexibleToday {
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return lhs.date < rhs.date
    }
}
