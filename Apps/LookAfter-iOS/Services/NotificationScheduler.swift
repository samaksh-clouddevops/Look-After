import Foundation
import UserNotifications
import LookAfterCore

/// Schedules and cancels local UNNotificationRequest instances.
actor NotificationScheduler {
    static let shared = NotificationScheduler()

    private let center = UNUserNotificationCenter.current()

    func apply(selected: [NotificationCandidate], preferences: NotificationPreferences) async {
        guard preferences.masterEnabled else {
            await cancelAllManaged()
            return
        }

        let pending = await center.pendingNotificationRequests()
        let managedIDs = Set(pending.compactMap(\.identifier).filter(isManagedIdentifier))
        let selectedIDs = Set(selected.map(\.id))

        for id in managedIDs where !selectedIDs.contains(id) {
            center.removePendingNotificationRequests(withIdentifiers: [id])
        }

        for candidate in selected {
            await schedule(candidate: candidate)
        }
    }

    func cancelAllManaged() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter(isManagedIdentifier)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func cancelFocusBreakNotifications() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(NotificationIdentifier.focusBreakPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func scheduleSnooze(for candidate: NotificationCandidate, fireDate: Date) async {
        let snoozed = NotificationCandidate(
            id: candidate.id,
            kind: candidate.kind,
            title: candidate.title,
            body: candidate.body,
            fireDate: fireDate,
            route: candidate.route,
            routePayload: candidate.routePayload
        )
        await schedule(candidate: snoozed)
    }

    // MARK: - Private

    private func schedule(candidate: NotificationCandidate) async {
        let content = UNMutableNotificationContent()
        content.title = candidate.title
        content.body = candidate.body
        content.sound = .default
        content.categoryIdentifier = candidate.kind == .focusBreak
            ? NotificationCategory.focusBreak.rawValue
            : NotificationCategory.proactive.rawValue
        content.userInfo = [
            NotificationPayloadKeys.kind: candidate.kind.rawValue,
            NotificationPayloadKeys.route: candidate.route.rawValue,
            NotificationPayloadKeys.candidateID: candidate.id
        ]
        if let payload = candidate.routePayload {
            content.userInfo[NotificationPayloadKeys.routePayload] = payload
        }

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: candidate.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: candidate.id, content: content, trigger: trigger)
        try? await center.add(request)
    }

    private func isManagedIdentifier(_ id: String) -> Bool {
        id.hasPrefix(NotificationIdentifier.proactivePrefix)
            || id.hasPrefix(NotificationIdentifier.focusBreakPrefix)
    }
}
