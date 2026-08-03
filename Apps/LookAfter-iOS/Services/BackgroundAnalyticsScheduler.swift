import Foundation
import LookAfterCore
import LookAfterData

/// Schedules background analytics refreshes on app lifecycle and data-change events.
@MainActor
final class BackgroundAnalyticsScheduler {

    static let shared = BackgroundAnalyticsScheduler()

    private let analytics = BackgroundAnalyticsService.shared
    private var observers: [NSObjectProtocol] = []
    private var overnightTimer: Timer?
    private var activeUserId: String = ""

    private init() {}

    func start(userId: String) {
        guard !userId.isEmpty else { return }
        activeUserId = userId
        installObservers()
        scheduleOvernightRefresh()
        analytics.scheduleRefresh(userId: userId, trigger: .appLaunch)
    }

    func handleAppBackground(userId: String) {
        guard !userId.isEmpty else { return }
        analytics.scheduleRefresh(userId: userId, trigger: .appBackground)
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        overnightTimer?.invalidate()
        overnightTimer = nil
    }

    // MARK: - Private

    private func installObservers() {
        guard observers.isEmpty else { return }

        let center = NotificationCenter.default

        observers.append(
            center.addObserver(
                forName: .analyticsDataDidChange,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self else { return }
                let reason = notification.userInfo?["reason"] as? String
                let trigger: AnalyticsRefreshTrigger
                switch reason {
                case AnalyticsDataChangeReason.taskCompleted.rawValue:
                    trigger = .taskCompleted
                case AnalyticsDataChangeReason.habitChanged.rawValue:
                    trigger = .habitChanged
                case AnalyticsDataChangeReason.healthSyncCompleted.rawValue:
                    trigger = .healthSyncCompleted
                default:
                    trigger = .manual
                }
                Task { @MainActor in
                    self.analytics.scheduleRefresh(userId: self.activeUserId, trigger: trigger)
                }
            }
        )
    }

    private func scheduleOvernightRefresh() {
        overnightTimer?.invalidate()

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.day = (components.day ?? 0) + 1
        components.hour = 4
        components.minute = 0

        guard let nextRun = calendar.date(from: components) else { return }
        let interval = max(60, nextRun.timeIntervalSinceNow)

        overnightTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.activeUserId.isEmpty else { return }
                self.analytics.scheduleRefresh(userId: self.activeUserId, trigger: .scheduled, force: true)
                self.scheduleOvernightRefresh()
            }
        }
    }
}
