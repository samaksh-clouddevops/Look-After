import Foundation

/// Lightweight calendar event for timeline aggregation.
public struct BriefingCalendarEvent: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let timeLabel: String
    public let endDate: Date?
    /// All-day EventKit events occupy flex placement only when `isBusy` (C2).
    public let isAllDay: Bool
    /// Free / transparent events do not occupy.
    public let isBusy: Bool

    public init(
        id: String,
        title: String,
        startDate: Date,
        timeLabel: String,
        endDate: Date? = nil,
        isAllDay: Bool = false,
        isBusy: Bool = true
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.timeLabel = timeLabel
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.isBusy = isBusy
    }
}

public enum ExecutiveTimelineBuilder {
    /// Life-oriented events for rich Today timeline UI.
    public static func buildLifeEvents(
        tasks: [LifeTask],
        completedToday: [LifeTask],
        recurrenceTemplates: [LifeTask] = [],
        bills: [BillItem],
        shoppingItems: [ShoppingItem],
        contacts: [RelationshipContact],
        calendarEvents: [BriefingCalendarEvent] = [],
        medications: [Medication] = [],
        now: Date = Date(),
        referenceDay: Date? = nil,
        calendar: Calendar = .current
    ) -> [LifeTimelineEvent] {
        LifeTimelinePresenter.build(
            tasks: tasks,
            completedToday: completedToday,
            recurrenceTemplates: recurrenceTemplates,
            bills: bills,
            shoppingItems: shoppingItems,
            contacts: contacts,
            calendarEvents: calendarEvents,
            medications: medications,
            now: now,
            referenceDay: referenceDay,
            calendar: calendar
        )
    }

    /// Events for tomorrow's preview timeline.
    public static func buildTomorrowLifeEvents(
        tasks: [LifeTask],
        recurrenceTemplates: [LifeTask] = [],
        bills: [BillItem],
        shoppingItems: [ShoppingItem],
        contacts: [RelationshipContact],
        calendarEvents: [BriefingCalendarEvent] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [LifeTimelineEvent] {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
            return []
        }
        return buildLifeEvents(
            tasks: tasks,
            completedToday: [],
            recurrenceTemplates: recurrenceTemplates,
            bills: bills,
            shoppingItems: shoppingItems,
            contacts: contacts,
            calendarEvents: calendarEvents,
            medications: [],
            now: now,
            referenceDay: tomorrow,
            calendar: calendar
        )
    }
}
