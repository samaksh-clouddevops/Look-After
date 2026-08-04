import Foundation
import UserNotifications
import LookAfterCore

@MainActor
final class NotificationRouter: ObservableObject {
    static let shared = NotificationRouter()

    @Published var pendingRoute: NotificationRoute?
    @Published var pendingRoutePayload: String?
    @Published var shouldOpenMedication = false
    @Published var shouldOpenTaskId: String?

    private init() {}

    func handleNotificationResponse(_ response: UNNotificationResponse) {
        let content = response.notification.request.content
        var userInfo = content.userInfo
        userInfo["title"] = content.title
        userInfo["body"] = content.body
        handleUserInfo(userInfo, actionIdentifier: response.actionIdentifier)
    }

    func handleUserInfo(_ userInfo: [AnyHashable: Any], actionIdentifier: String? = nil) {
        guard let routeRaw = userInfo[NotificationPayloadKeys.route] as? String,
              let route = NotificationRoute(rawValue: routeRaw) else { return }

        let candidateID = userInfo[NotificationPayloadKeys.candidateID] as? String
        let payload = userInfo[NotificationPayloadKeys.routePayload] as? String

        if actionIdentifier == NotificationAction.dismissToday.rawValue, let candidateID {
            NotificationDailyBudgetStore.dismissForToday(candidateID: candidateID)
            return
        }

        if actionIdentifier == NotificationAction.snooze15.rawValue, let candidateID {
            let snoozeUntil = Date().addingTimeInterval(TimeInterval(NotificationPolicy.snoozeMinutes * 60))
            NotificationDailyBudgetStore.snooze(candidateID: candidateID, until: snoozeUntil)
            Task {
                await NotificationCoordinator.shared.refreshAfterSnooze(
                    candidateID: candidateID,
                    fireDate: snoozeUntil,
                    userInfo: userInfo
                )
            }
            return
        }

        applyRoute(route, payload: payload)
    }

    func applyRoute(_ route: NotificationRoute, payload: String?) {
        pendingRoute = route
        pendingRoutePayload = payload
        shouldOpenMedication = route == .medication
        shouldOpenTaskId = route == .task ? payload : nil
    }

    func consumeRoute() -> (NotificationRoute, String?)? {
        guard let route = pendingRoute else { return nil }
        let payload = pendingRoutePayload
        pendingRoute = nil
        pendingRoutePayload = nil
        shouldOpenMedication = false
        shouldOpenTaskId = nil
        return (route, payload)
    }
}
