import Foundation
@preconcurrency import EventKit
import LookAfterCore
#if os(iOS)
import UIKit
#endif

public enum CalendarSyncError: Error {
    case accessDenied
    case generic(String)
}

public final class CalendarSyncService {
    private let eventStore = EKEventStore()
    private static let lookAfterCalendarTitle = "Look After"
    private static let lookAfterCalendarKey = "lookafter.calendar.dedicatedCalendarIdentifier"

    public init() {}

    /// Legacy entry point — forwards to upserting sync for today.
    public func syncToCalendar(tasks: [LifeTask]) async throws {
        _ = try await syncScheduledTasks(tasks, on: Date())
    }

    /// Creates or updates busy blocks on Apple Calendar for scheduled tasks on the given day.
    /// Returns tasks whose `calendarEventIdentifier` changed (for persistence).
    @discardableResult
    public func syncScheduledTasks(
        _ tasks: [LifeTask],
        on day: Date,
        calendar: Calendar = .current
    ) async throws -> [LifeTask] {
        guard CalendarSyncSettings.syncTasksToAppleCalendar else { return [] }

        let granted = try await requestCalendarAccess()
        guard granted else { throw CalendarSyncError.accessDenied }

        let targetCalendar = try resolveLookAfterCalendar()
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            throw CalendarSyncError.generic("Could not resolve day boundary.")
        }

        var changedTasks: [LifeTask] = []
        var activeEventIDs = Set<String>()
        let relevant = tasks.filter { task in
            guard let scheduledTime = task.scheduledTime else { return false }
            let anchor = task.scheduledDate ?? scheduledTime
            return calendar.isDate(anchor, inSameDayAs: day) || calendar.isDate(scheduledTime, inSameDayAs: day)
        }

        for var task in relevant {
            let day = calendar.startOfDay(for: task.scheduledDate ?? Date())
            if TaskScheduleInterval.isPlaceholderMidnightSchedule(for: task, calendar: calendar)
                || TaskScheduleInterval.displaySchedule(for: task, on: day) == .unslottedFlexible {
                if let eventID = task.calendarEventIdentifier {
                    removeEvent(identifier: eventID)
                    task.calendarEventIdentifier = nil
                    changedTasks.append(task)
                }
                continue
            }

            let shouldRemove = !task.status.isActive
                || task.scheduledTime == nil
                || task.isRecurrenceTemplateTask

            if shouldRemove {
                if let eventID = task.calendarEventIdentifier {
                    removeEvent(identifier: eventID)
                    task.calendarEventIdentifier = nil
                    changedTasks.append(task)
                }
                continue
            }

            guard let scheduledTime = task.scheduledTime else { continue }

            let event: EKEvent
            if let eventID = task.calendarEventIdentifier,
               let existing = eventStore.event(withIdentifier: eventID) {
                event = existing
            } else {
                event = EKEvent(eventStore: eventStore)
                event.calendar = targetCalendar
            }

            event.title = task.title
            event.notes = calendarNotes(for: task)
            event.startDate = scheduledTime
            event.endDate = resolvedEndDate(for: task, start: scheduledTime)
            event.availability = .busy
            event.isAllDay = false
            event.calendar = targetCalendar

            do {
                try eventStore.save(event, span: .thisEvent, commit: false)
                if let newID = event.eventIdentifier {
                    activeEventIDs.insert(newID)
                    if task.calendarEventIdentifier != newID {
                        task.calendarEventIdentifier = newID
                        changedTasks.append(task)
                    }
                }
            } catch {
                print("[CalendarSync] Failed to save \"\(task.title)\": \(error.localizedDescription)")
            }
        }

        pruneOrphanedEvents(
            on: dayStart...dayEnd,
            calendar: targetCalendar,
            activeEventIDs: activeEventIDs
        )

        try eventStore.commit()
        return changedTasks
    }

    // MARK: - Private

    private func requestCalendarAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    private func resolveLookAfterCalendar() throws -> EKCalendar {
        if let storedID = UserDefaults.standard.string(forKey: Self.lookAfterCalendarKey),
           let stored = eventStore.calendar(withIdentifier: storedID) {
            return stored
        }

        if let existing = eventStore.calendars(for: .event).first(where: {
            $0.title == Self.lookAfterCalendarTitle
        }) {
            UserDefaults.standard.set(existing.calendarIdentifier, forKey: Self.lookAfterCalendarKey)
            return existing
        }

        guard let source = eventStore.defaultCalendarForNewEvents?.source
            ?? eventStore.sources.first(where: { $0.sourceType == .local || $0.sourceType == .calDAV }) else {
            throw CalendarSyncError.generic("No calendar source available.")
        }

        let created = EKCalendar(for: .event, eventStore: eventStore)
        created.title = Self.lookAfterCalendarTitle
        created.source = source
        #if os(iOS)
        created.cgColor = UIColor.systemIndigo.cgColor
        #endif
        try eventStore.saveCalendar(created, commit: true)
        UserDefaults.standard.set(created.calendarIdentifier, forKey: Self.lookAfterCalendarKey)
        return created
    }

    private func resolvedEndDate(for task: LifeTask, start: Date) -> Date {
        if let end = task.scheduledEndTime, end > start { return end }
        let durationMinutes = task.estimatedMinutes > 0 ? task.estimatedMinutes : 30
        return Calendar.current.date(byAdding: .minute, value: durationMinutes, to: start) ?? start.addingTimeInterval(30 * 60)
    }

    private func calendarNotes(for task: LifeTask) -> String {
        var lines = ["Blocked by Look After"]
        if !task.description.isEmpty { lines.append(task.description) }
        if task.estimatedMinutes > 0 { lines.append("Estimated: \(task.estimatedMinutes) min") }
        return lines.joined(separator: "\n")
    }

    private func removeEvent(identifier: String) {
        guard let event = eventStore.event(withIdentifier: identifier) else { return }
        do {
            try eventStore.remove(event, span: .thisEvent, commit: false)
        } catch {
            print("[CalendarSync] Failed to remove event: \(error.localizedDescription)")
        }
    }

    private func pruneOrphanedEvents(
        on interval: ClosedRange<Date>,
        calendar: EKCalendar,
        activeEventIDs: Set<String>
    ) {
        let predicate = eventStore.predicateForEvents(withStart: interval.lowerBound, end: interval.upperBound, calendars: [calendar])
        let events = eventStore.events(matching: predicate)
        for event in events {
            guard let id = event.eventIdentifier else { continue }
            guard !activeEventIDs.contains(id) else { continue }
            guard event.notes?.contains("Blocked by Look After") == true else { continue }
            removeEvent(identifier: id)
        }
    }

    /// Today's Apple Calendar events for the live timeline (excludes Look After busy blocks).
    public func briefingEvents(on day: Date = Date(), calendar: Calendar = .current) -> [BriefingCalendarEvent] {
        let status = EKEventStore.authorizationStatus(for: .event)
        let authorized = status == .fullAccess || status == .writeOnly
        guard authorized else { return [] }

        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone

        return eventStore.events(matching: predicate)
            .filter { event in
                event.calendar?.title != Self.lookAfterCalendarTitle
                    && event.notes?.contains("Blocked by Look After") != true
            }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                let busy: Bool
                switch event.availability {
                case .free, .tentative:
                    busy = false
                default:
                    busy = true
                }
                return BriefingCalendarEvent(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Event",
                    startDate: event.startDate,
                    timeLabel: event.isAllDay ? "All day" : formatter.string(from: event.startDate),
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    isBusy: busy
                )
            }
    }
}
