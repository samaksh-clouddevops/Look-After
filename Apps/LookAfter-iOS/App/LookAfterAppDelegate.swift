import Foundation
import UIKit
import UserNotifications
import LookAfterCore
import LookAfterData
import LookAfterFeatures

final class LookAfterAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        LookAfterFirebaseConfiguration.configureIfNeeded()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        LookAfterFirebaseConfiguration.configureIfNeeded()
        UNUserNotificationCenter.current().delegate = self
        // BG tasks must register before app finishes launching.
        BackgroundNotificationRefreshTask.register()
        BehavioralTelemetryBackgroundTask.register()
        BehavioralTelemetryBackgroundTask.scheduleNext()
        // Starvation protocol: catch up if vault older than 48h (BGTask is best-effort).
        TelemetrySynthesizerService.shared.catchUpIfStarved()
        // Speech voice APIs must not run inside a Swift Task (iOS 26 AXCoreUtilities
        // unsafeForcedSync). Bootstrap hops to GCD main itself.
        AppleSpeechVoiceBootstrap.startIfNeeded()
        Task { @MainActor in
            AppleCredentialMonitor.startIfNeeded()
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
