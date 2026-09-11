import Foundation

/// Chronological timeline ordering — interleaves unslotted flexibles into the current day gap.
public enum TimelineDisplaySort {

    public static func isSleepBoundary(_ event: LifeTimelineEvent) -> Bool {
        event.id.hasPrefix("sleep-boundary")
    }

    /// True when the event has no concrete clock slot (shows "Flexible today").
    public static func isUnslottedFlexible(_ event: LifeTimelineEvent) -> Bool {
        guard event.scheduleKind.isFlexibleToday || event.isFlexibleToday else { return false }
        if event.scheduleKind == .fixedWindow { return false }
        if event.subtitle.contains(" – "), !event.subtitle.hasPrefix("About ") {
            let rangePart = event.subtitle.components(separatedBy: " · ").last ?? event.subtitle
            if rangePart.contains(" – ") { return false }
        }
        return true
    }

    public static func sorted(
        _ events: [LifeTimelineEvent],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [LifeTimelineEvent] {
        events.sorted { compare($0, $1, among: events, now: now, calendar: calendar) }
    }

    public static func compare(
        _ lhs: LifeTimelineEvent,
        _ rhs: LifeTimelineEvent,
        among events: [LifeTimelineEvent],
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        if lhs.id.hasPrefix("sleep-boundary") != rhs.id.hasPrefix("sleep-boundary") {
            return !lhs.id.hasPrefix("sleep-boundary")
        }

        let lhsKey = sortKey(for: lhs, among: events, now: now, calendar: calendar)
        let rhsKey = sortKey(for: rhs, among: events, now: now, calendar: calendar)
        if lhsKey != rhsKey { return lhsKey < rhsKey }

        if isUnslottedFlexible(lhs), isUnslottedFlexible(rhs) {
            if lhs.sortPriority != rhs.sortPriority {
                return lhs.sortPriority > rhs.sortPriority
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        return lhs.date < rhs.date
    }

    public static func sortKey(
        for event: LifeTimelineEvent,
        among events: [LifeTimelineEvent],
        now: Date,
        calendar: Calendar = .current
    ) -> Date {
        if event.isCompleted || !isUnslottedFlexible(event) {
            return event.date
        }
        return gapInsertionTime(now: now, among: events, calendar: calendar)
    }

    /// Whether `now` falls in an open gap between timed blocks (candidate for flexible work).
    public static func isInSchedulingGap(
        now: Date,
        among events: [LifeTimelineEvent],
        calendar: Calendar = .current
    ) -> Bool {
        let timed = events.filter {
            !$0.isCompleted && !isUnslottedFlexible($0) && !$0.id.hasPrefix("sleep-boundary")
        }
        let inActiveWindow = timed.contains { event in
            event.date <= now && now <= event.resolvedEndDate(calendar: calendar)
        }
        if inActiveWindow { return false }

        let nextStart = timed.filter { $0.date > now }.map(\.date).min()
        if let nextStart, now < nextStart { return true }

        let lastEnd = timed.filter { $0.resolvedEndDate(calendar: calendar) <= now }
            .map { $0.resolvedEndDate(calendar: calendar) }
            .max()
        if lastEnd != nil, nextStart == nil { return true }
        return lastEnd != nil && nextStart != nil
    }

    private static func gapInsertionTime(
        now: Date,
        among events: [LifeTimelineEvent],
        calendar: Calendar
    ) -> Date {
        let timed = events.filter {
            !$0.isCompleted && !isUnslottedFlexible($0) && !$0.id.hasPrefix("sleep-boundary")
        }

        let nextStart = timed.filter { $0.date > now }.map(\.date).min()
        if let nextStart {
            let lastEnd = timed
                .filter { $0.resolvedEndDate(calendar: calendar) <= now }
                .map { $0.resolvedEndDate(calendar: calendar) }
                .max()
            if let lastEnd {
                return min(max(now, lastEnd), nextStart)
            }
            return min(now, nextStart)
        }

        if let lastEnd = timed.map({ $0.resolvedEndDate(calendar: calendar) }).max() {
            return max(now, lastEnd)
        }
        return now
    }
}
