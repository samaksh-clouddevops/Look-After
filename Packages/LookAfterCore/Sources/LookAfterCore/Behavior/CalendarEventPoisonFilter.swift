import Foundation

// MARK: - Calendar poison control

/// Metadata flags mapped from EKEvent / EKCalendar at the app edge (Core stays EventKit-free).
public struct CalendarEventSourceMeta: Sendable, Equatable {
    public var isAllDay: Bool
    public var isSubscribedCalendar: Bool
    public var calendarTitle: String
    public var eventTitle: String

    public init(
        isAllDay: Bool = false,
        isSubscribedCalendar: Bool = false,
        calendarTitle: String = "",
        eventTitle: String = ""
    ) {
        self.isAllDay = isAllDay
        self.isSubscribedCalendar = isSubscribedCalendar
        self.calendarTitle = calendarTitle
        self.eventTitle = eventTitle
    }
}

/// Drops holidays, PTO, birthdays, subscribed spam before K-means.
public enum CalendarEventPoisonFilter {
    public static let blockedTitleSubstrings: [String] = [
        "birthday", "pto", "oof", "out of office", "vacation", "holiday",
        "flight", "time off", "ooo", "day off", "leave"
    ]

    public static func shouldInclude(
        event: CalendarHistoryEvent,
        meta: CalendarEventSourceMeta? = nil
    ) -> Bool {
        let isAllDay = meta?.isAllDay ?? event.isAllDay
        if isAllDay { return false }
        if meta?.isSubscribedCalendar == true { return false }

        let title = (meta?.eventTitle.isEmpty == false ? meta!.eventTitle : event.title)
            .lowercased()
        let cal = (meta?.calendarTitle ?? "").lowercased()

        for token in blockedTitleSubstrings {
            if title.contains(token) || cal.contains(token) { return false }
        }

        // Duration sanity already partly handled by analyzer; keep ultra-long blocks out.
        if event.durationMinutes >= 12 * 60 { return false }
        if event.durationMinutes < 5 { return false }
        return true
    }

    public static func filter(
        _ events: [CalendarHistoryEvent],
        metaByID: [String: CalendarEventSourceMeta] = [:]
    ) -> [CalendarHistoryEvent] {
        events.filter { shouldInclude(event: $0, meta: metaByID[$0.id]) }
    }

    /// Convenience when meta is embedded on a parallel array of equal length.
    public static func filter(
        events: [CalendarHistoryEvent],
        metas: [CalendarEventSourceMeta]
    ) -> [CalendarHistoryEvent] {
        zip(events, metas).compactMap { event, meta in
            shouldInclude(event: event, meta: meta) ? event : nil
        }
    }
}
