import Foundation
import UserNotifications

@MainActor
final class NotificationPermissionService: ObservableObject {
    static let shared = NotificationPermissionService()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()

    private init() {
        Task { await refreshStatus() }
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    var isDenied: Bool {
        authorizationStatus == .denied
    }

    func refreshStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        if ProcessInfo.processInfo.arguments.contains("-SimulateNotificationDenied") {
            authorizationStatus = .denied
            return false
        }

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshStatus()
            if granted, PushCapabilities.hasRemotePushEntitlement {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            return granted
        } catch {
            await refreshStatus()
            return false
        }
    }

    func registerCategories() {
        let startNow = UNNotificationAction(
            identifier: NotificationAction.startNow.rawValue,
            title: "Start now",
            options: [.foreground]
        )
        let snooze = UNNotificationAction(
            identifier: NotificationAction.snooze15.rawValue,
            title: "Snooze 15m",
            options: []
        )
        let dismissToday = UNNotificationAction(
            identifier: NotificationAction.dismissToday.rawValue,
            title: "Dismiss today",
            options: [.destructive]
        )

        let category = UNNotificationCategory(
            identifier: NotificationCategory.proactive.rawValue,
            actions: [startNow, snooze, dismissToday],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let focusCategory = UNNotificationCategory(
            identifier: NotificationCategory.focusBreak.rawValue,
            actions: [startNow],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        center.setNotificationCategories([category, focusCategory])
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

enum NotificationCategory: String {
    case proactive = "lookafter.proactive"
    case focusBreak = "lookafter.focusBreak"
}

enum NotificationAction: String {
    case startNow = "lookafter.action.startNow"
    case snooze15 = "lookafter.action.snooze15"
    case dismissToday = "lookafter.action.dismissToday"
}

#if canImport(UIKit)
import UIKit
#endif
