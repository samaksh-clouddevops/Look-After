import Foundation
import FirebaseAuth
import FirebaseFirestore
import LookAfterCore
import LookAfterData

/// Orchestrates candidate building, policy selection, and local scheduling.
@MainActor
final class NotificationCoordinator {
    static let shared = NotificationCoordinator()

    private let calendarProvider = EventKitCalendarEnvironmentSignalProvider()
    private var lastRefreshAt: Date?
    private let minRefreshInterval: TimeInterval = 30

    private init() {}

    func configureOnLaunch() {
        NotificationPermissionService.shared.registerCategories()
        BackgroundNotificationRefreshTask.register()
        BackgroundNotificationRefreshTask.scheduleNextRefresh()
    }

    func refreshFromShell(_ shell: AppShellState) async {
        guard NotificationPermissionService.shared.isAuthorized else {
            await NotificationScheduler.shared.cancelAllManaged()
            return
        }

        if let lastRefreshAt, Date().timeIntervalSince(lastRefreshAt) < minRefreshInterval {
            return
        }
        lastRefreshAt = Date()

        let now = Date()
        let calendarSignals = await calendarProvider.currentSignals(at: now)
        let postWake = PostWakeDetector.evaluate(
            PostWakeDetector.Input(
                now: now,
                wakeTime: shell.brainVM.healthSummary?.wakeTime,
                lastBackgroundAt: PostWakeSessionStore.lastBackgroundAt(),
                dismissedOnDay: PostWakeSessionStore.dismissedOnDay()
            )
        )

        let heroTask = shell.brainVM.flowSurface?.heroTask
            ?? shell.brainVM.topTasks.first
            ?? shell.tasksVM.tasks.first(where: { $0.status.isActive })

        var focusBreakDate: Date?
        var focusToken: String?
        if shell.adhdVM.isFocusSessionActive, !shell.adhdVM.isOnBreak {
            let remaining = max(0, shell.adhdVM.focusSessionTarget - shell.adhdVM.focusSessionElapsed)
            focusBreakDate = now.addingTimeInterval(remaining)
            focusToken = shell.adhdVM.sessionLabel
        }

        // Schedule-driven deep work / creative / health blocks suppress low-priority noise
        // the same way a manual ADHD focus session does.
        let executionSuppresses = ExecutionFocusFilterStore.shared.suppressLowPriority
        let focusActive = shell.adhdVM.isFocusSessionActive || executionSuppresses

        let input = NotificationRefreshInput(
            now: now,
            medications: MedicationStore.load(),
            tasks: shell.tasksVM.tasks,
            nextCalendarEvent: calendarSignals.nextEvent,
            postWake: postWake,
            heroTaskTitle: heroTask.map(\.title),
            heroTaskId: heroTask?.id,
            focusSessionActive: focusActive,
            focusBreakFireDate: focusBreakDate,
            focusSessionToken: focusToken,
            userDisplayName: UserLifeProfileStore.resolvedDisplayName(),
            proactiveActions: shell.proactiveActions.filter { $0.surface == .notification }
        )

        await refresh(input: input)
    }

    func refresh(input: NotificationRefreshInput) async {
        let preferences = NotificationPreferencesStore.load()
        guard preferences.globallyEnabled else {
            await NotificationScheduler.shared.cancelAllManaged()
            return
        }

        let budget = NotificationDailyBudgetStore.load(now: input.now)
        let candidates = NotificationCandidateBuilder.build(from: input)
        let selection = NotificationPolicyEngine.select(
            candidates: candidates,
            preferences: preferences,
            budget: budget,
            now: input.now
        )

        await NotificationScheduler.shared.apply(selected: selection.selected, preferences: preferences)
        await syncPendingToCloud(candidates: selection.selected, budget: budget)
    }

    private func syncPendingToCloud(candidates: [NotificationCandidate], budget: ProactiveDailyBudget) async {
        guard FirebaseManager.shared.isCloudSyncAvailable,
              let db = FirebaseManager.shared.db else { return }
        let uid = FirebaseManager.shared.resolvedUserId
        guard !uid.isEmpty else { return }

        let proactive = candidates.filter(\.kind.countsTowardDailyCap).map { candidate -> [String: Any] in
            [
                "id": candidate.id,
                "kind": candidate.kind.rawValue,
                "title": candidate.title,
                "body": candidate.body,
                "route": candidate.route.rawValue,
                "routePayload": candidate.routePayload ?? "",
                "fireAt": candidate.fireDate.timeIntervalSince1970
            ]
        }

        let payload: [String: Any] = [
            "budgetDay": budget.dayKey,
            "deliveredCount": budget.deliveredCount,
            "candidates": proactive,
            "updatedAt": Date().timeIntervalSince1970
        ]

        try? await db.collection("users")
            .document(uid)
            .collection("notificationState")
            .document("pending")
            .setData(payload, merge: true)
    }

    func refreshAfterFocusSessionEnded() async {
        await NotificationScheduler.shared.cancelFocusBreakNotifications()
    }

    func refreshAfterSnooze(candidateID: String, fireDate: Date, userInfo: [AnyHashable: Any]) async {
        guard let kindRaw = userInfo[NotificationPayloadKeys.kind] as? String,
              let kind = NotificationKind(rawValue: kindRaw),
              let routeRaw = userInfo[NotificationPayloadKeys.route] as? String,
              let route = NotificationRoute(rawValue: routeRaw) else { return }

        let title = (userInfo["title"] as? String) ?? kind.displayName
        let body = (userInfo["body"] as? String) ?? ""
        let payload = userInfo[NotificationPayloadKeys.routePayload] as? String

        let candidate = NotificationCandidate(
            id: candidateID,
            kind: kind,
            title: title,
            body: body,
            fireDate: fireDate,
            route: route,
            routePayload: payload
        )
        await NotificationScheduler.shared.scheduleSnooze(for: candidate, fireDate: fireDate)
    }

    func resetForFactoryReset() async {
        NotificationPreferencesStore.resetForFactoryReset()
        NotificationDailyBudgetStore.resetForFactoryReset()
        ProactiveFeedbackStore.resetForFactoryReset()
        ProactiveDismissStore.resetForFactoryReset()
        ProactiveSnapshotStore.resetForFactoryReset()
        ProactivePreviewTimeoutStore.clear()
        ExperimentReminderStore.resetForFactoryReset()
        await NotificationScheduler.shared.cancelAllManaged()
    }
}
