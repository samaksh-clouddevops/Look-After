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

    @Published var pendingProactiveKind: String?
    @Published var pendingSpeakBody: String?

    private init() {}

    func handleNotificationResponse(_ response: UNNotificationResponse) {
        let content = response.notification.request.content
        var userInfo = content.userInfo
        userInfo["title"] = content.title
        userInfo["body"] = content.body
        handleUserInfo(userInfo, actionIdentifier: response.actionIdentifier)
    }

    func handleUserInfo(_ userInfo: [AnyHashable: Any], actionIdentifier: String? = nil) {
        let candidateID = userInfo[NotificationPayloadKeys.candidateID] as? String
        let proactiveKindRaw = userInfo[NotificationPayloadKeys.proactiveKind] as? String

        if actionIdentifier == UNNotificationDismissActionIdentifier, let candidateID {
            NotificationDailyBudgetStore.dismissForToday(candidateID: candidateID)
            if let proactiveKindRaw, let kind = ProactiveAction.Kind(rawValue: proactiveKindRaw) {
                ProactiveFeedbackStore.record(kind: kind, outcome: .dismissed)
                ProactiveDismissStore.dismissKindForToday(kind: kind)
            }
            return
        }

        guard let routeRaw = userInfo[NotificationPayloadKeys.route] as? String,
              let route = NotificationRoute(rawValue: routeRaw) else { return }

        let payload = userInfo[NotificationPayloadKeys.routePayload] as? String

        if actionIdentifier == NotificationAction.dismissToday.rawValue, let candidateID {
            NotificationDailyBudgetStore.dismissForToday(candidateID: candidateID)
            if let proactiveKindRaw, let kind = ProactiveAction.Kind(rawValue: proactiveKindRaw) {
                ProactiveFeedbackStore.record(kind: kind, outcome: .dismissed)
                ProactiveDismissStore.dismissKindForToday(kind: kind)
            }
            return
        }

        if actionIdentifier == NotificationAction.snooze15.rawValue, let candidateID {
            let snoozeUntil = Date().addingTimeInterval(TimeInterval(NotificationPolicy.snoozeMinutes * 60))
            NotificationDailyBudgetStore.snooze(candidateID: candidateID, until: snoozeUntil)
            if let proactiveKindRaw, let kind = ProactiveAction.Kind(rawValue: proactiveKindRaw) {
                ProactiveFeedbackStore.record(kind: kind, outcome: .snoozed)
                ProactiveDismissStore.snooze(kind: kind, until: snoozeUntil)
            }
            Task {
                await NotificationCoordinator.shared.refreshAfterSnooze(
                    candidateID: candidateID,
                    fireDate: snoozeUntil,
                    userInfo: userInfo
                )
            }
            return
        }

        if actionIdentifier == NotificationAction.startNow.rawValue {
            if let proactiveKindRaw, let kind = ProactiveAction.Kind(rawValue: proactiveKindRaw) {
                ProactiveFeedbackStore.record(kind: kind, outcome: .accepted)
            }
        }

        if actionIdentifier == UNNotificationDefaultActionIdentifier || actionIdentifier == NotificationAction.startNow.rawValue {
            pendingSpeakBody = userInfo["body"] as? String
        }

        applyRoute(route, payload: payload, proactiveKind: proactiveKindRaw)
    }

    func applyRoute(_ route: NotificationRoute, payload: String?, proactiveKind: String? = nil) {
        pendingRoute = route
        pendingRoutePayload = payload
        pendingProactiveKind = proactiveKind
        shouldOpenMedication = route == .medication
        shouldOpenTaskId = route == .task ? payload : nil
    }

    func consumeRoute() -> (NotificationRoute, String?, String?)? {
        guard let route = pendingRoute else { return nil }
        let payload = pendingRoutePayload
        let proactiveKind = pendingProactiveKind
        pendingRoute = nil
        pendingRoutePayload = nil
        pendingProactiveKind = nil
        shouldOpenMedication = false
        shouldOpenTaskId = nil
        return (route, payload, proactiveKind)
    }

    func consumeSpeakBody() -> String? {
        let body = pendingSpeakBody
        pendingSpeakBody = nil
        return body
    }
}
