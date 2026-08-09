import Foundation
import LookAfterCore
import LookAfterData
import LookAfterHealth

/// Configures app state when launched under XCUITest (`-UITesting`).
enum UITestLaunchConfiguration {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITesting")
    }

    static func applyIfNeeded() {
        guard isEnabled else { return }

        UserDefaults.standard.set(true, forKey: "enableHealth")
        UserDefaults.standard.set(false, forKey: "enableFlowDirector")

        let seedFlow = argumentValue(prefix: "-SeedFlow") ?? "FLOW-002"
        let userId = "uitest-\(seedFlow.lowercased())"
        UserDefaults.standard.set(userId, forKey: "saved_user_uid")
        UserDefaults.standard.set("uitest@lookafter.test", forKey: "userEmail")

        var profile = UserLifeProfileStore.load()
        profile.hasCompletedOnboarding = !ProcessInfo.processInfo.arguments.contains("-ShowOnboarding")
        profile.preferredName = "UITest User"
        if ProcessInfo.processInfo.arguments.contains("-ShowFeatureTour") {
            AppFeatureTourStore.reset()
        } else {
            AppFeatureTourStore.markCompleted()
        }
        if profile.profileText.isEmpty {
            profile.profileText = """
            # UITest Profile
            - Morning routine: review tasks
            - Evening: journal
            """
        }
        UserLifeProfileStore.save(profile)

        if ProcessInfo.processInfo.arguments.contains("-SkipLiveActivity") {
            UserDefaults.standard.set(false, forKey: "enableHealth")
        }

        MainActor.assumeIsolated {
            FirebaseManager.shared.currentUserId = userId
            FirebaseManager.shared.isAuthenticated = true
            FirebaseManager.shared.userEmail = "uitest@lookafter.test"
        }

        if ProcessInfo.processInfo.arguments.contains("-SimulateOffline") {
            UserDefaults.standard.set(true, forKey: "uitest_simulate_offline")
        }
        if ProcessInfo.processInfo.arguments.contains("-SimulateNotificationDenied") {
            var prefs = NotificationPreferencesStore.load()
            prefs.globallyEnabled = true
            NotificationPreferencesStore.save(prefs)
        }
        if let category = argumentValue(prefix: "-UIPreferredContentSizeCategory") {
            UserDefaults.standard.set(category, forKey: "uitest_content_size_category")
        }
        if ProcessInfo.processInfo.arguments.contains("-ReduceMotion") {
            UserDefaults.standard.set(true, forKey: "uitest_reduce_motion")
        }
        if let mockHealthStatus = argumentValue(prefix: "-MockHealthStatus") {
            UserDefaults.standard.set(mockHealthStatus, forKey: "uitest_mock_health_status")
        }

        if UserDefaults.standard.string(forKey: "uitest_mock_health_status") != nil {
            MainActor.assumeIsolated {
                HealthSyncService.shared.refreshConnectionStatus(userId: userId)
            }
        }
    }

    static var shouldAutoStartFocusSession: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains("-AutoStartFocusSession")
    }

    static var shouldSkipLiveActivity: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains("-SkipLiveActivity")
    }

    static var shouldSeedFocusTask: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains("-SeedFocusTask")
    }

    static let focusTaskId = "uitest-focus-task"

    static func argumentValue(prefix: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: prefix), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }
}
