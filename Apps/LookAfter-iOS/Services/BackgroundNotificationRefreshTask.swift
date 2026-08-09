import BackgroundTasks
import Foundation
import LookAfterCore
import LookAfterData

/// Lightweight background pass — reload calendar, meds, and tasks; reschedule local notifications.
enum BackgroundNotificationRefreshTask {
    static let identifier = "com.samaksh.flowos.app.notification-refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    static func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        scheduleNextRefresh()

        let work = Task {
            await performDeterministicRefresh()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            work.cancel()
        }
    }

    @MainActor
    private static func performDeterministicRefresh() async {
        let userId = FirebaseManager.shared.resolvedUserId

        // Phase 2: drain durable cloud outbox even when notifications are off.
        if ArchitectureFeatureFlags.useSyncOutbox, !userId.isEmpty {
            SyncOutboxWorker.shared.setTransport(FirestoreSyncOutboxTransport())
            _ = await SyncOutboxWorker.shared.drainOnce(userId: userId)
        }

        guard NotificationPermissionService.shared.isAuthorized else { return }
        guard NotificationPreferencesStore.load().globallyEnabled else { return }

        let now = Date()
        let calendarProvider = EventKitCalendarEnvironmentSignalProvider()
        let calendarSignals = await calendarProvider.currentSignals(at: now)
        let medications = MedicationStore.load()
        let snapshot = TaskStore.shared.localSnapshot(for: userId)
        let tasks = snapshot.active

        let postWake = PostWakeDetector.evaluate(
            PostWakeDetector.Input(
                now: now,
                lastBackgroundAt: PostWakeSessionStore.lastBackgroundAt(),
                dismissedOnDay: PostWakeSessionStore.dismissedOnDay()
            )
        )

        let heroTask = tasks.first(where: { $0.status.isActive })

        let input = NotificationRefreshInput(
            now: now,
            medications: medications,
            tasks: tasks,
            nextCalendarEvent: calendarSignals.nextEvent,
            postWake: postWake,
            heroTaskTitle: heroTask?.title,
            heroTaskId: heroTask?.id,
            userDisplayName: UserLifeProfileStore.resolvedDisplayName(),
            proactiveActions: ProactiveSnapshotStore.load().filter { $0.surface == .notification }
        )

        await NotificationCoordinator.shared.refresh(input: input)
    }
}
