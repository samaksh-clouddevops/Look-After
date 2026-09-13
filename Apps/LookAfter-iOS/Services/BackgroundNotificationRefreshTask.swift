import BackgroundTasks
import Foundation
import LookAfterCore
import LookAfterData

/// Lightweight background pass — reload calendar, meds, and tasks; reschedule local notifications.
enum BackgroundNotificationRefreshTask {
    /// Legacy ID still registered in Info.plist / BGTaskSchedulerPermittedIdentifiers.
    static let legacyIdentifier = "com.samaksh.flowos.app.notification-refresh"
    /// Brand ID — dual-register when Info.plist lists both (Phase 7.3).
    static let modernIdentifier = "com.lookafter.app.notification-refresh"
    /// Primary schedule target remains legacy until dual Info.plist lands.
    static let identifier = legacyIdentifier
    private static var didRegister = false

    static func register() {
        guard !didRegister else { return }
        didRegister = true
        for id in [legacyIdentifier, modernIdentifier] {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { task in
                guard let refreshTask = task as? BGAppRefreshTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                handle(refreshTask)
            }
        }
    }

    static func scheduleNextRefresh() {
        // Prefer modern if submit succeeds (Info.plist must allow it); else legacy.
        let modern = BGAppRefreshTaskRequest(identifier: modernIdentifier)
        modern.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(modern)
        } catch {
            let legacy = BGAppRefreshTaskRequest(identifier: legacyIdentifier)
            legacy.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
            try? BGTaskScheduler.shared.submit(legacy)
        }
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
