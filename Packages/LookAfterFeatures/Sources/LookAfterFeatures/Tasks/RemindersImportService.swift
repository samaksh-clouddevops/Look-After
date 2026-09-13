import Foundation
@preconcurrency import EventKit
import LookAfterCore

public enum RemindersImportError: Error {
    case accessDenied
}

/// Imports Apple Reminders (`EKReminder`) as `LifeTask` rows.
/// Mirrors `CalendarSyncService`'s EventKit access pattern but targets `.reminder` entities.
public final class RemindersImportService {
    private let eventStore = EKEventStore()

    public init() {}

    /// Fetches incomplete reminders and maps them to `LifeTask` drafts, ready for `TasksViewModel.createTaskAndAwait`.
    /// Caller is responsible for de-duplicating against existing tasks and persisting.
    public func fetchIncompleteReminders(userId: String) async throws -> [LifeTask] {
        let granted = try await requestRemindersAccess()
        guard granted else { throw RemindersImportError.accessDenied }

        let reminders = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[LifeTask], Error>) in
            let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            eventStore.fetchReminders(matching: predicate) { fetched in
                let tasks = (fetched ?? []).compactMap { self.mapToLifeTask($0, userId: userId) }
                continuation.resume(returning: tasks)
            }
        }

        return reminders
    }

    // MARK: - Private

    private func requestRemindersAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToReminders()
    }

    private func mapToLifeTask(_ reminder: EKReminder, userId: String) -> LifeTask? {
        guard let title = reminder.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let dueDate = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
        let priority = mapPriority(reminder.priority)

        return LifeTask(
            title: title,
            description: reminder.notes ?? "",
            lifeArea: .personal,
            priority: priority,
            estimatedMinutes: 15,
            deadline: dueDate,
            scheduledDate: dueDate,
            scheduledTime: reminder.dueDateComponents?.hour != nil ? dueDate : nil,
            tags: ["reminders-import"],
            notes: "Imported from Reminders",
            schedulingMode: .flexible,
            userId: userId
        )
    }

    /// EKReminder.priority: 0 = none, 1-4 = high, 5 = medium, 6-9 = low (Apple's scale).
    private func mapPriority(_ ekPriority: Int) -> Priority {
        switch ekPriority {
        case 1...4: return .high
        case 5: return .medium
        case 6...9: return .low
        default: return .medium
        }
    }
}
