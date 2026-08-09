import Foundation

/// Resolves the timeline NOW marker — shared by Today timeline UI and pin-to-lock-screen.
public enum TimelineNowResolver {

    /// Events sorted chronologically with unslotted flexibles in the current gap.
    public static func sortedEvents(_ events: [LifeTimelineEvent], now: Date = Date()) -> [LifeTimelineEvent] {
        TimelineDisplaySort.sorted(events, now: now)
    }

    /// The event marked NOW on the Today timeline at `now`.
    public static func currentNowEvent(
        in events: [LifeTimelineEvent],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> LifeTimelineEvent? {
        let sorted = sortedEvents(events, now: now)
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
            guard !event.isCompleted, !TimelineDisplaySort.isUnslottedFlexible(event) else { continue }
            let end = event.resolvedEndDate(calendar: calendar)
            if event.date <= now, now <= end { return index }
        }

        if TimelineDisplaySort.isInSchedulingGap(now: now, among: events, calendar: calendar),
           let gapIndex = events.firstIndex(where: {
               !$0.isCompleted && TimelineDisplaySort.isUnslottedFlexible($0)
           }) {
            return gapIndex
        }

        if let upcoming = events.firstIndex(where: {
            !$0.isCompleted && !TimelineDisplaySort.isUnslottedFlexible($0) && $0.date > now
        }) {
            return upcoming
        }

        return events.firstIndex(where: {
            !$0.isCompleted && TimelineDisplaySort.isUnslottedFlexible($0)
        })
    }

    public static func taskId(from eventId: String) -> String? {
        guard eventId.hasPrefix("task-") else { return nil }
        let id = String(eventId.dropFirst(5))
        return id.isEmpty ? nil : id
    }
}
