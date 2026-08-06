import Foundation
import SwiftUI
import LookAfterCore

/// Immutable snapshot of today and tomorrow timeline events.
public struct TimelineSnapshot: Sendable, Equatable {
    public let today: [LifeTimelineEvent]
    public let tomorrow: [LifeTimelineEvent]

    public init(today: [LifeTimelineEvent], tomorrow: [LifeTimelineEvent]) {
        self.today = today
        self.tomorrow = tomorrow
    }

    public static let empty = TimelineSnapshot(today: [], tomorrow: [])
}

/// Optimistic timeline patch applied before the next full rebuild.
public enum TimelinePatch: Sendable, Equatable {
    case completed(taskId: String)
    case rescheduled(taskId: String, to: Date)
}

/// Projects `[LifeTimelineEvent]` into timeline rows for the Today UI.
public enum TimelineRowProjector {
    public static func rows(from events: [LifeTimelineEvent], now: Date = Date()) -> [ExecutivePlanningTimelineRow] {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        let sorted = events.sorted(by: timelineEventSortOrder)
        let currentIndex = currentEventIndex(in: sorted, now: now)

        return sorted.enumerated().map { index, event in
            row(from: event, index: index, currentIndex: currentIndex, now: now, formatter: formatter, isPreview: false)
        }
    }

    public static func previewRows(from events: [LifeTimelineEvent]) -> [ExecutivePlanningTimelineRow] {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let sorted = events.sorted(by: timelineEventSortOrder)
        return sorted.enumerated().map { index, event in
            row(from: event, index: index, currentIndex: nil, now: Date(), formatter: formatter, isPreview: true)
        }
    }

    public static func applyPatch(_ patch: TimelinePatch, to rows: [ExecutivePlanningTimelineRow]) -> [ExecutivePlanningTimelineRow] {
        var updated = rows
        switch patch {
        case .completed(let taskId):
            guard let index = updated.firstIndex(where: { $0.taskId == taskId && !$0.isCompleted }) else { return rows }
            updated[index].isCompleted = true
            updated[index].isNow = false
            updated[index].isPast = false
            updated[index].subtitle = "Done"
            updated[index].completedAt = Date()
        case .rescheduled(let taskId, let newTime):
            guard let index = updated.firstIndex(where: { $0.taskId == taskId }) else { return rows }
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            updated[index].sortDate = newTime
            updated[index].timeLabel = formatter.string(from: newTime)
            if let minutes = updated[index].estimatedMinutes {
                let end = newTime.addingTimeInterval(TimeInterval(minutes * 60))
                updated[index].endTimeLabel = formatter.string(from: end)
                updated[index].scheduleRangeLabel = ScheduleTimeFormatting.rangeLabel(from: newTime, to: end)
            }
            updated[index].isPast = false
            updated[index].isNow = false
            updated[index].change = .moved
        }
        return updated
    }

    // MARK: - Private

    private static func row(
        from event: LifeTimelineEvent,
        index: Int,
        currentIndex: Int?,
        now: Date,
        formatter: DateFormatter,
        isPreview: Bool
    ) -> ExecutivePlanningTimelineRow {
        let isFlexible = event.isFlexibleToday
        let end = event.resolvedEndDate()
        let endLabel = isFlexible ? "" : formatter.string(from: end)
        let rangeLabel = isFlexible
            ? ""
            : ScheduleTimeFormatting.rangeLabel(from: event.date, to: end)
        let isPast = !isPreview && !event.isCompleted && !isFlexible && end < now
        let isCompleted = event.isCompleted
        let isNow = !isPreview && !isCompleted && !isPast && currentIndex == index
        let timeLabel = isFlexible
            ? "Flexible"
            : formatter.string(from: event.date)

        return ExecutivePlanningTimelineRow(
            id: event.id,
            sortDate: isFlexible ? end : event.date,
            timeLabel: timeLabel,
            endTimeLabel: endLabel,
            scheduleRangeLabel: rangeLabel,
            title: event.title,
            subtitle: previewSubtitle(for: event, isPast: isPast, isCompleted: isCompleted, isPreview: isPreview),
            detailLines: event.detailLines,
            kind: event.kind,
            isNow: isNow,
            isCompleted: isCompleted,
            isPast: isPast,
            taskId: taskId(from: event.id),
            estimatedMinutes: event.estimatedMinutes,
            completedAt: event.completedAt,
            isFixedEvent: event.isFixed,
            timeConstraint: event.isFixed ? .anchored : .flexible
        )
    }

    private static func previewSubtitle(
        for event: LifeTimelineEvent,
        isPast: Bool,
        isCompleted: Bool,
        isPreview: Bool
    ) -> String {
        if isPreview {
            if event.isFixed { return "Fixed commitment" }
            return event.subtitle.isEmpty ? "Planned" : event.subtitle
        }
        return subtitle(for: event, isPast: isPast, isCompleted: isCompleted)
    }

    private static func subtitle(for event: LifeTimelineEvent, isPast: Bool, isCompleted: Bool) -> String {
        if isCompleted { return "Done" }
        if isPast { return "Window passed" }
        return event.subtitle
    }

    private static func taskId(from eventId: String) -> String? {
        guard eventId.hasPrefix("task-") else { return nil }
        let id = String(eventId.dropFirst(5))
        return id.isEmpty ? nil : id
    }

    private static func currentEventIndex(in events: [LifeTimelineEvent], now: Date) -> Int? {
        for (index, event) in events.enumerated() {
            guard !event.isCompleted else { continue }
            let end = event.resolvedEndDate()
            if event.date <= now, now <= end { return index }
        }
        return events.firstIndex { !$0.isCompleted && $0.date > now }
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

/// Single owner for day timelines — builds events once and projects UI rows.
@MainActor
public final class TimelineService: ObservableObject {
    public static let shared = TimelineService()

    @Published public private(set) var snapshot: TimelineSnapshot = .empty
    @Published public private(set) var todayRows: [ExecutivePlanningTimelineRow] = []
    @Published public private(set) var tomorrowRows: [ExecutivePlanningTimelineRow] = []

    private var pendingPatches: [TimelinePatch] = []
    private var patchVersion: Int = 0

    public init() {}

    public func rebuild(
        tasks: [LifeTask],
        completedToday: [LifeTask],
        recurrenceTemplates: [LifeTask],
        bills: [BillItem],
        shoppingItems: [ShoppingItem],
        contacts: [RelationshipContact],
        medications: [Medication],
        calendarEvents: [BriefingCalendarEvent] = [],
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let today = LifeTimelinePresenter.build(
            tasks: tasks,
            completedToday: completedToday,
            recurrenceTemplates: recurrenceTemplates,
            bills: bills,
            shoppingItems: shoppingItems,
            contacts: contacts,
            calendarEvents: calendarEvents,
            medications: medications,
            now: now,
            calendar: calendar
        )
        let tomorrow: [LifeTimelineEvent]
        if let tomorrowDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            tomorrow = LifeTimelinePresenter.build(
                tasks: tasks,
                completedToday: [],
                recurrenceTemplates: recurrenceTemplates,
                bills: bills,
                shoppingItems: shoppingItems,
                contacts: contacts,
                calendarEvents: calendarEvents,
                medications: [],
                now: now,
                referenceDay: tomorrowDay,
                calendar: calendar
            )
        } else {
            tomorrow = []
        }

        snapshot = TimelineSnapshot(today: today, tomorrow: tomorrow)
        pendingPatches = []
        patchVersion += 1
        projectRows(now: now, animated: false)
    }

    public func applyPatch(_ patch: TimelinePatch) {
        pendingPatches.append(patch)
        let patched = pendingPatches.reduce(todayRows) { rows, patch in
            TimelineRowProjector.applyPatch(patch, to: rows)
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            todayRows = patched
        }
    }

    public func projectRows(now: Date = Date(), animated: Bool = true) {
        let built = TimelineRowProjector.rows(from: snapshot.today, now: now)
        let tomorrowBuilt = TimelineRowProjector.previewRows(from: snapshot.tomorrow)
        if animated {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                todayRows = built
                tomorrowRows = tomorrowBuilt
            }
        } else {
            todayRows = built
            tomorrowRows = tomorrowBuilt
        }
    }

    public func factoryReset() {
        snapshot = .empty
        todayRows = []
        tomorrowRows = []
        pendingPatches = []
    }
}
