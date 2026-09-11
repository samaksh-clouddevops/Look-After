import BackgroundTasks
import Foundation
import LookAfterCore
import LookAfterData

/// Lightweight background pass — reload calendar, meds, and tasks; reschedule local notifications.
enum BackgroundNotificationRefreshTask {
    static let identifier = "com.samaksh.flowos.app.notification-refresh"
    private static var didRegister = false

    static func register() {
        guard !didRegister else { return }
        didRegister = true
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

        let completion = BackgroundTaskCompletion(task)
        let work = Task {
            await performDeterministicRefresh()
            completion.finish(success: true)
        }

        task.expirationHandler = {
            work.cancel()
            completion.finish(success: false)
        }
    }

    @MainActor
    private static func performDeterministicRefresh() async {
        guard NotificationPermissionService.shared.isAuthorized else { return }
        guard NotificationPreferencesStore.load().globallyEnabled else { return }

        let now = Date()
        let calendarProvider = EventKitCalendarEnvironmentSignalProvider()
        let calendarSignals = await calendarProvider.currentSignals(at: now)
        let medications = MedicationStore.load()
        let userId = FirebaseManager.shared.resolvedUserId
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
        let leanBody = DaySupervisorContinuity.leanNotificationBody(
            from: DayAuditService.run(
                DayAuditService.Input(
                    tasks: tasks,
                    parkedCandidates: ParkedTaskQueueStore.shared.candidatesForReintegration(limit: 5),
                    now: now
                )
            )
        )

        let input = NotificationRefreshInput(
            now: now,
            medications: medications,
            tasks: tasks,
            nextCalendarEvent: calendarSignals.nextEvent,
            postWake: postWake,
            heroTaskTitle: heroTask?.title,
            heroTaskId: heroTask?.id,
            userDisplayName: UserLifeProfileStore.resolvedDisplayName(),
            proactiveActions: ProactiveSnapshotStore.load().filter { $0.surface == .notification },
            dayAuditLeanBody: leanBody
        )

        await NotificationCoordinator.shared.refresh(input: input)
        _ = await TaskSyncOutbox.shared.drain()
    }
}

/// Ensures `setTaskCompleted` runs exactly once (success path or expiration).
private final class BackgroundTaskCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let task: BGTask

    init(_ task: BGTask) {
        self.task = task
    }

    func finish(success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        task.setTaskCompleted(success: success)
    }
}
