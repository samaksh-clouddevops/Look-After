import Foundation
import UIKit
import UserNotifications
import LookAfterCore
import LookAfterData

final class LookAfterAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            NotificationCoordinator.shared.configureOnLaunch()
            await NotificationPermissionService.shared.refreshStatus()
            if PushCapabilities.hasRemotePushEntitlement {
                FirebaseMessagingService.shared.configureIfAvailable()
            }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            FirebaseMessagingService.shared.setAPNSToken(deviceToken)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Local notifications still work without APNs — expected in Simulator.
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if let candidateID = notification.request.content.userInfo[NotificationPayloadKeys.candidateID] as? String,
           let kindRaw = notification.request.content.userInfo[NotificationPayloadKeys.kind] as? String,
           let kind = NotificationKind(rawValue: kindRaw),
           kind.countsTowardDailyCap {
            NotificationDailyBudgetStore.recordDelivered(candidateID: candidateID)
        }
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            NotificationRouter.shared.handleNotificationResponse(response)
        }
        completionHandler()
    }
}
