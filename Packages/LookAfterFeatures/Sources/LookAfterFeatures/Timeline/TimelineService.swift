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
    case uncompleted(taskId: String)
    case rescheduled(taskId: String, to: Date)
}

/// Projects `[LifeTimelineEvent]` into timeline rows for the Today UI.
public enum TimelineRowProjector {
    public static func rows(from events: [LifeTimelineEvent], now: Date = Date(), calendar: Calendar = .current) -> [ExecutivePlanningTimelineRow] {
        let formatter = dateFormatter(calendar: calendar)

        let sorted = TimelineNowResolver.sortedEvents(events, now: now)
        let currentIndex = TimelineNowResolver.currentEventIndex(in: sorted, now: now, calendar: calendar)

        return sorted.enumerated().map { index, event in
            row(
                from: event,
                index: index,
                currentIndex: currentIndex,
                now: now,
                allEvents: sorted,
                formatter: formatter,
                isPreview: false,
                calendar: calendar
            )
        }
    }

    public static func previewRows(from events: [LifeTimelineEvent], calendar: Calendar = .current) -> [ExecutivePlanningTimelineRow] {
        let formatter = dateFormatter(calendar: calendar)
        let sorted = TimelineNowResolver.sortedEvents(events)
        return sorted.enumerated().map { index, event in
            row(
                from: event,
                index: index,
                currentIndex: nil,
                now: Date(),
                allEvents: sorted,
                formatter: formatter,
                isPreview: true,
                calendar: calendar
            )
        }
    }

    private static func dateFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = .current
        return formatter
    }

    public static func applyPatch(
        _ patch: TimelinePatch,
        to rows: [ExecutivePlanningTimelineRow],
        now: Date = Date()
    ) -> [ExecutivePlanningTimelineRow] {
        var updated = rows
        switch patch {
        case .completed(let taskId):
            guard let index = updated.firstIndex(where: { $0.taskId == taskId && !$0.isCompleted }) else { return rows }
            updated[index].isCompleted = true
            updated[index].isNow = false
            updated[index].isPast = false
            updated[index].subtitle = "Done"
            updated[index].completedAt = Date()
        case .uncompleted(let taskId):
            guard let index = updated.firstIndex(where: { $0.taskId == taskId && $0.isCompleted }) else { return rows }
            updated[index].isCompleted = false
            updated[index].completedAt = nil
            updated[index].subtitle = "Planned"
            updated[index].isPast = false
            updated[index].isNow = false
        case .rescheduled(let taskId, let newTime):
            guard let index = updated.firstIndex(where: { $0.taskId == taskId }) else { return rows }
            let formatter = dateFormatter(calendar: .current)
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
            updated[index].isUnslottedFlexible = false
            return resortRows(updated, now: now)
        }
        return resortRows(updated, now: now)
    }

    private static func resortRows(_ rows: [ExecutivePlanningTimelineRow], now: Date = Date()) -> [ExecutivePlanningTimelineRow] {
        var sorted = rows.sorted { lhs, rhs in
            let lhsUnslotted = isUnslottedFlexibleRow(lhs)
            let rhsUnslotted = isUnslottedFlexibleRow(rhs)
            if lhsUnslotted != rhsUnslotted {
                // Defer to chronological keys — slotted rows keep sortDate, unslotted use gap anchor below.
            }
            let lhsKey = lhsUnslotted ? gapSortDate(for: lhs, rows: rows, now: now) : lhs.sortDate
            let rhsKey = rhsUnslotted ? gapSortDate(for: rhs, rows: rows, now: now) : rhs.sortDate
            if lhsKey != rhsKey { return lhsKey < rhsKey }
            if lhsUnslotted, rhsUnslotted {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.sortDate < rhs.sortDate
        }

        var currentIndex: Int?
        for (index, row) in sorted.enumerated() {
            guard !row.isCompleted, !row.isSuggestedSlot, !isUnslottedFlexibleRow(row) else { continue }
            guard !row.id.hasPrefix("sleep-boundary") else { continue }
            let minutes = row.estimatedMinutes ?? 30
            let end = row.sortDate.addingTimeInterval(TimeInterval(minutes * 60))
            if row.sortDate <= now, now <= end {
                currentIndex = index
                break
            }
        }
        if currentIndex == nil {
            var latestOverdue: (Int, Date)?
            for (index, row) in sorted.enumerated() {
                guard !row.isCompleted, !row.isSuggestedSlot, !isUnslottedFlexibleRow(row) else { continue }
                guard !row.id.hasPrefix("sleep-boundary") else { continue }
                let end = row.sortDate.addingTimeInterval(TimeInterval((row.estimatedMinutes ?? 30) * 60))
                if end < now, row.sortDate < now {
                    if latestOverdue == nil || end > latestOverdue!.1 {
                        latestOverdue = (index, end)
                    }
                }
            }
            currentIndex = latestOverdue?.0
        }
        if currentIndex == nil,
           hasSchedulingGap(in: sorted, now: now),
           let gapIndex = sorted.firstIndex(where: { !$0.isCompleted && !$0.isSuggestedSlot && isUnslottedFlexibleRow($0) }) {
            currentIndex = gapIndex
        }
        if currentIndex == nil {
            currentIndex = sorted.firstIndex {
                !$0.isCompleted && !$0.isSuggestedSlot && !isUnslottedFlexibleRow($0)
                    && !$0.id.hasPrefix("sleep-boundary") && $0.sortDate > now
            }
        }
        for index in sorted.indices {
            sorted[index].isNow = currentIndex == index && !sorted[index].isCompleted && !sorted[index].isSuggestedSlot
        }
        return sorted
    }

    private static func isUnslottedFlexibleRow(_ row: ExecutivePlanningTimelineRow) -> Bool {
        row.isUnslottedFlexible
    }

    private static func gapSortDate(
        for row: ExecutivePlanningTimelineRow,
        rows: [ExecutivePlanningTimelineRow],
        now: Date
    ) -> Date {
        let slotted = rows.filter { !isUnslottedFlexibleRow($0) && !$0.isCompleted }
        let nextStart = slotted.filter { $0.sortDate > now }.map(\.sortDate).min()
        if let nextStart {
            let lastEnd = slotted
                .filter { $0.sortDate.addingTimeInterval(TimeInterval(($0.estimatedMinutes ?? 30) * 60)) <= now }
                .map { $0.sortDate.addingTimeInterval(TimeInterval(($0.estimatedMinutes ?? 30) * 60)) }
                .max()
            if let lastEnd { return min(max(now, lastEnd), nextStart) }
            return min(now, nextStart)
        }
        return now
    }

    private static func hasSchedulingGap(in rows: [ExecutivePlanningTimelineRow], now: Date) -> Bool {
        let slotted = rows.filter { !$0.isCompleted && !isUnslottedFlexibleRow($0) }
        let inWindow = slotted.contains { row in
            let end = row.sortDate.addingTimeInterval(TimeInterval((row.estimatedMinutes ?? 30) * 60))
            return row.sortDate <= now && now <= end
        }
        if inWindow { return false }
        return slotted.contains { $0.sortDate > now }
            || slotted.contains {
                $0.sortDate.addingTimeInterval(TimeInterval(($0.estimatedMinutes ?? 30) * 60)) <= now
            }
    }

    // MARK: - Private

    private static func row(
        from event: LifeTimelineEvent,
        index: Int,
        currentIndex: Int?,
        now: Date,
        allEvents: [LifeTimelineEvent],
        formatter: DateFormatter,
        isPreview: Bool,
        calendar: Calendar = .current
    ) -> ExecutivePlanningTimelineRow {
        let isFlexible = event.scheduleKind.isFlexibleToday || event.isFlexibleToday
        let dayStart = calendar.startOfDay(for: now)
        var isUnslotted = TimelineDisplaySort.isUnslottedFlexible(event)
        if !isUnslotted,
           event.id.hasPrefix("task-"),
           TaskScheduleInterval.isDisplayMidnightSentinel(event.date, on: dayStart, calendar: calendar) {
            isUnslotted = true
        }
        if !isUnslotted,
           event.isCompleted,
           event.id.hasPrefix("task-"),
           TaskScheduleInterval.isDisplayMidnightSentinel(event.date, on: dayStart, calendar: calendar) {
            isUnslotted = true
        }
        let end = isFlexible
            ? (event.date.addingTimeInterval(TimeInterval((event.estimatedMinutes ?? 30) * 60)))
            : event.resolvedEndDate(calendar: calendar)
        let rangeLabel: String
        if isUnslotted {
            rangeLabel = ""
        } else if event.subtitle.contains(" – ") {
            let rangePart = event.subtitle.components(separatedBy: " · ").last ?? event.subtitle
            rangeLabel = rangePart.contains(" – ") ? rangePart : ScheduleTimeFormatting.rangeLabel(from: event.date, to: end)
        } else if !isFlexible {
            rangeLabel = ScheduleTimeFormatting.rangeLabel(from: event.date, to: end)
        } else {
            rangeLabel = ScheduleTimeFormatting.rangeLabel(from: event.date, to: end)
        }
        let isPast = !isPreview && !event.isCompleted && !isFlexible && end < now
        let isCompleted = event.isCompleted
        let isNow = !isPreview && !isCompleted && currentIndex == index
        let isLate = isNow && isPast
        let displaySortDate = isUnslotted && !isCompleted
            ? TimelineDisplaySort.sortKey(for: event, among: allEvents, now: now, calendar: calendar)
            : event.date
        let durationMinutes = event.estimatedMinutes ?? 30
        // Unslotted flexibles use gap-anchor only for sort order — never paint a fake wall clock
        // (that made every unslotted task look like it started at `now` / Dinner).
        var timeLabel = ""
        var endLabel = ""
        if !isUnslotted {
            timeLabel = formatter.string(from: event.date)
            endLabel = formatter.string(from: end)
            if timeLabel == "12:00 AM", event.id.hasPrefix("task-") {
                if isCompleted {
                    timeLabel = ""
                    endLabel = ""
                } else {
                    timeLabel = formatter.string(from: displaySortDate)
                    endLabel = formatter.string(from: displaySortDate.addingTimeInterval(TimeInterval(durationMinutes * 60)))
                    if timeLabel == "12:00 AM" {
                        timeLabel = ""
                        endLabel = ""
                    }
                }
            }
        }

        return ExecutivePlanningTimelineRow(
            id: event.id,
            sortDate: displaySortDate,
            timeLabel: timeLabel,
            endTimeLabel: endLabel,
            scheduleRangeLabel: rangeLabel,
            title: event.title,
            subtitle: previewSubtitle(for: event, isPast: isPast, isCompleted: isCompleted, isLate: isLate, isPreview: isPreview),
            detailLines: event.detailLines,
            kind: event.kind,
            isNow: isNow,
            isCompleted: isCompleted,
            isPast: isPast,
            isLate: isLate,
            taskId: TimelineNowResolver.taskId(from: event.id),
            estimatedMinutes: event.estimatedMinutes,
            completedAt: event.completedAt,
            isFixedEvent: event.isFixed,
            timeConstraint: event.resolvedTimeConstraint,
            scheduleKind: event.scheduleKind,
            isUnslottedFlexible: isUnslotted && !isCompleted
        )
    }

    private static func previewSubtitle(
        for event: LifeTimelineEvent,
        isPast: Bool,
        isCompleted: Bool,
        isLate: Bool,
        isPreview: Bool
    ) -> String {
        if isPreview {
            if event.isFixed { return "Fixed commitment" }
            return event.subtitle.isEmpty ? "Planned" : event.subtitle
        }
        return subtitle(for: event, isPast: isPast, isCompleted: isCompleted, isLate: isLate)
    }

    private static func subtitle(for event: LifeTimelineEvent, isPast: Bool, isCompleted: Bool, isLate: Bool) -> String {
        if isCompleted { return "Done" }
        if isLate { return "Late" }
        if isPast { return "Window passed" }
        return event.subtitle
    }

    /// Display-only rows for flexible tasks that could not be persisted (overcommitted day).
    public static func suggestedSlotRows(
        tasks: [LifeTask],
        completedToday: [LifeTask],
        existingRows: [ExecutivePlanningTimelineRow],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ExecutivePlanningTimelineRow] {
        let dayStart = calendar.startOfDay(for: now)
        let existingTaskIds = Set(existingRows.compactMap(\.taskId))
        let pool = tasks + completedToday

        let unslotted = tasks.filter { task in
            guard task.status.isActive, task.isSchedulerMovable else { return false }
            guard !existingTaskIds.contains(task.id) else { return false }
            if let scheduledDate = task.scheduledDate {
                guard calendar.isDate(scheduledDate, inSameDayAs: dayStart) else { return false }
            } else if !calendar.isDateInToday(now) {
                return false
            }
            return !TaskScheduleInterval.hasConcreteTimelineSlot(for: task, on: dayStart, calendar: calendar)
        }
        guard !unslotted.isEmpty else { return [] }

        let plan = DaySchedulePlanner.plan(tasks: pool, on: dayStart, now: now, calendar: calendar)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        return unslotted.compactMap { task in
            guard let slot = plan.slots.first(where: { $0.taskID == task.id }) else { return nil }
            let startLabel = formatter.string(from: slot.start)
            let endLabel = formatter.string(from: slot.end)
            let title = UserFacingCopy.sanitize(task.title).isEmpty ? task.title : UserFacingCopy.sanitize(task.title)
            return ExecutivePlanningTimelineRow(
                id: "suggested-\(task.id)",
                sortDate: slot.start,
                timeLabel: "~\(startLabel)",
                endTimeLabel: endLabel,
                scheduleRangeLabel: ScheduleTimeFormatting.rangeLabel(from: slot.start, to: slot.end),
                title: title,
                subtitle: "Suggested — day is tight",
                kind: LifeTimelineKindResolver.kind(for: task),
                taskId: nil,
                estimatedMinutes: task.estimatedMinutes,
                timeConstraint: task.timeConstraintValue,
                scheduleKind: .floating,
                isSuggestedSlot: true,
                suggestedStart: slot.start,
                suggestedSourceTaskId: task.id,
                isUnslottedFlexible: true
            )
        }
    }

    public static func mergeWithSuggestedRows(
        _ base: [ExecutivePlanningTimelineRow],
        suggested: [ExecutivePlanningTimelineRow],
        now: Date = Date()
    ) -> [ExecutivePlanningTimelineRow] {
        guard !suggested.isEmpty else { return base }
        return resortRows(base + suggested, now: now)
    }

}

/// Single owner for day timelines — builds events once and projects UI rows.
@MainActor
public final class TimelineService: ObservableObject {
    public static let shared = TimelineService()

    @Published public private(set) var snapshot: TimelineSnapshot = .empty
    @Published public private(set) var todayRows: [ExecutivePlanningTimelineRow] = []
    @Published public private(set) var tomorrowRows: [ExecutivePlanningTimelineRow] = []

    private var lastRebuildTasks: [LifeTask] = []
    private var lastRebuildCompleted: [LifeTask] = []
    private var lastProjectedNow: Date = Date()
    private var nowClockTask: Task<Void, Never>?

    public init() {}

    /// Task id for the rail NOW/LATE row — single source for Today hero and timeline.
    public var nowTaskId: String? {
        todayRows.first(where: { $0.isNow && !$0.isCompleted })?.taskId
    }

    public func startNowClock() {
        nowClockTask?.cancel()
        nowClockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled, let self else { return }
                self.projectNow(now: Date())
            }
        }
    }

    public func stopNowClock() {
        nowClockTask?.cancel()
        nowClockTask = nil
    }

    public func projectNow(now: Date = Date(), calendar: Calendar = .current) {
        lastProjectedNow = now
        projectRows(now: now, animated: false, calendar: calendar)
    }

    public func rebuild(
        tasks: [LifeTask],
        completedToday: [LifeTask],
        recurrenceTemplates: [LifeTask],
        bills: [BillItem],
        shoppingItems: [ShoppingItem],
        contacts: [RelationshipContact],
        medications: [Medication],
        calendarEvents: [BriefingCalendarEvent] = [],
        tomorrowCalendarEvents: [BriefingCalendarEvent]? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        lastRebuildTasks = tasks
        lastRebuildCompleted = completedToday
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
            let tomorrowEvents = tomorrowCalendarEvents
                ?? calendarEvents.filter { calendar.isDate($0.startDate, inSameDayAs: tomorrowDay) || $0.isAllDay }
            tomorrow = LifeTimelinePresenter.build(
                tasks: tasks,
                completedToday: [],
                recurrenceTemplates: recurrenceTemplates,
                bills: bills,
                shoppingItems: shoppingItems,
                contacts: contacts,
                calendarEvents: tomorrowEvents,
                medications: [],
                now: now,
                referenceDay: tomorrowDay,
                calendar: calendar
            )
        } else {
            tomorrow = []
        }

        snapshot = TimelineSnapshot(today: today, tomorrow: tomorrow)
        lastProjectedNow = now
        projectRows(now: now, animated: false)
    }

    public func applyPatch(_ patch: TimelinePatch) {
        switch patch {
        case .completed(let taskId):
            snapshot = TimelineSnapshot(
                today: snapshot.today.map { event in
                    TimelineNowResolver.taskId(from: event.id) == taskId
                        ? event.withCompletion(true, at: Date())
                        : event
                },
                tomorrow: snapshot.tomorrow
            )
        case .uncompleted(let taskId):
            snapshot = TimelineSnapshot(
                today: snapshot.today.map { event in
                    TimelineNowResolver.taskId(from: event.id) == taskId
                        ? event.withCompletion(false, at: nil)
                        : event
                },
                tomorrow: snapshot.tomorrow
            )
        case .rescheduled(let taskId, let newTime):
            snapshot = TimelineSnapshot(
                today: snapshot.today.map { event in
                    TimelineNowResolver.taskId(from: event.id) == taskId
                        ? event.withDate(newTime)
                        : event
                },
                tomorrow: snapshot.tomorrow
            )
        }
        projectRows(now: lastProjectedNow, animated: true)
    }

    public func projectRows(now: Date = Date(), animated: Bool = true, calendar: Calendar = .current) {
        lastProjectedNow = now
        let base = TimelineRowProjector.rows(from: snapshot.today, now: now)
        let suggested = TimelineRowProjector.suggestedSlotRows(
            tasks: lastRebuildTasks,
            completedToday: lastRebuildCompleted,
            existingRows: base,
            now: now,
            calendar: calendar
        )
        let built = TimelineRowProjector.mergeWithSuggestedRows(base, suggested: suggested, now: now)
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
        stopNowClock()
    }
}
