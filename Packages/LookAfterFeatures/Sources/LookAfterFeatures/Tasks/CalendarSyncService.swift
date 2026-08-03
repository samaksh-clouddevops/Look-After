import Foundation
import EventKit
import LookAfterCore

public enum CalendarSyncError: Error {
    case accessDenied
    case generic(String)
}

public final class CalendarSyncService: Sendable {
    private let eventStore = EKEventStore()

    public init() {}

    /// Syncs a list of LifeTasks to the Apple Calendar as events.
    public func syncToCalendar(tasks: [LifeTask]) async throws {
        // Request write-only access for iOS 17+ / macOS 14+
        var granted = false
        if #available(iOS 17.0, macOS 14.0, *) {
            granted = try await eventStore.requestWriteOnlyAccessToEvents()
        } else {
            granted = try await eventStore.requestAccess(to: .event)
        }

        guard granted else {
            throw CalendarSyncError.accessDenied
        }

        guard let defaultCalendar = eventStore.defaultCalendarForNewEvents else {
            throw CalendarSyncError.generic("No default calendar found.")
        }

        for task in tasks {
            // Only sync tasks that have a scheduled time
            guard let scheduledTime = task.scheduledTime else { continue }
            
            let event = EKEvent(eventStore: eventStore)
            event.title = task.title
            event.notes = task.description
            event.startDate = scheduledTime
            if let endTime = task.scheduledEndTime, endTime > scheduledTime {
                event.endDate = endTime
            } else {
                let durationMinutes = task.estimatedMinutes > 0 ? task.estimatedMinutes : 30
                event.endDate = calendarDate(byAdding: .minute, value: durationMinutes, to: scheduledTime)
            }
            event.calendar = defaultCalendar
            
            do {
                try eventStore.save(event, span: .thisEvent)
            } catch {
                print("Failed to save event for task \(task.title): \(error.localizedDescription)")
                // we can optionally continue or throw
            }
        }
    }
    
    private func calendarDate(byAdding component: Calendar.Component, value: Int, to date: Date) -> Date {
        return Calendar.current.date(byAdding: component, value: value, to: date) ?? date
    }
}
