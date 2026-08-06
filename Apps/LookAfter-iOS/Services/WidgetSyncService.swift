import Foundation
import WidgetKit
import LookAfterCore
import LookAfterData
import LookAfterFeatures

/// Builds widget snapshot from app state and refreshes home screen + pinned Live Activity.
@MainActor
final class WidgetSyncService {

    static let shared = WidgetSyncService()

    private let pinNowKey = "pinNowToLockScreen"

    private(set) var lastPinResult: PinNowResult?

    private init() {}

    var isNowPinned: Bool {
        UserDefaults.standard.bool(forKey: pinNowKey)
    }

    @discardableResult
    func setNowPinned(_ pinned: Bool, shell: AppShellState? = nil) async -> PinNowResult {
        if pinned {
            let snapshot: WidgetSnapshot
            if let shell {
                shell.rebuildTimelineFromTasks()
                snapshot = makeSnapshot(
                    brainVM: shell.brainVM,
                    taskStore: shell.taskStore,
                    healthStore: shell.healthStore,
                    scheduleTasks: shell.tasksVM.tasks + shell.tasksVM.completedToday,
                    timelineEvents: shell.timelineService.snapshot.today
                )
                WidgetDataStore.save(snapshot)
                WidgetCenter.shared.reloadAllTimelines()
                PinNowLogger.info(
                    "sync before pin — timelineNow=\(TimelineNowResolver.currentNowEvent(in: shell.timelineService.snapshot.today)?.title ?? "nil"), topTask=\(snapshot.topTaskTitle ?? "nil"), active=\(snapshot.activeTaskCount), appGroup=\(WidgetDataStore.isAvailable)"
                )
            } else {
                snapshot = WidgetDataStore.load()
                PinNowLogger.info("pin without shell — loaded disk topTask=\(snapshot.topTaskTitle ?? "nil")")
            }

            guard let title = snapshot.resolvedTopTaskTitle else {
                UserDefaults.standard.set(false, forKey: pinNowKey)
                let result = PinNowResult.failed("No next step to pin. Add or open a task first.")
                lastPinResult = result
                PinNowLogger.error(result.message)
                return result
            }

            // Reserve the pin slot before Activity.request so execution layer won't preempt.
            UserDefaults.standard.set(true, forKey: pinNowKey)
            let startResult = await LiveActivityManager.shared.startNowPin(from: snapshot)
            lastPinResult = startResult
            if startResult.success {
                PinNowLogger.info("Pinned \"\(title)\" to Lock Screen")
            } else {
                UserDefaults.standard.set(false, forKey: pinNowKey)
            }
            return startResult
        } else {
            UserDefaults.standard.set(false, forKey: pinNowKey)
            await LiveActivityManager.shared.endNowPinAndWait()
            ExecutionEnvironmentCoordinator.shared.refresh(forceLiveActivity: true)
            let result = PinNowResult.ok("Unpinned from Lock Screen")
            lastPinResult = result
            PinNowLogger.info(result.message)
            return result
        }
    }

    func sync(
        brainVM: BrainViewModel,
        taskStore: TaskStore,
        healthStore: HealthStore = .shared,
        scheduleTasks: [LifeTask]? = nil,
        timelineEvents: [LifeTimelineEvent]? = nil
    ) {
        let snapshot = makeSnapshot(
            brainVM: brainVM,
            taskStore: taskStore,
            healthStore: healthStore,
            scheduleTasks: scheduleTasks,
            timelineEvents: timelineEvents
        )
        WidgetDataStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()

        if isNowPinned {
            schedulePinRefresh(snapshot: snapshot)
        }
    }

    /// Rebuilds and pushes the latest task state to the pinned Live Activity.
    func refreshPinNow(
        brainVM: BrainViewModel,
        taskStore: TaskStore,
        healthStore: HealthStore = .shared,
        scheduleTasks: [LifeTask],
        timelineEvents: [LifeTimelineEvent]? = nil
    ) async {
        guard isNowPinned else { return }
        let snapshot = makeSnapshot(
            brainVM: brainVM,
            taskStore: taskStore,
            healthStore: healthStore,
            scheduleTasks: scheduleTasks,
            timelineEvents: timelineEvents
        )
        WidgetDataStore.save(snapshot)
        if snapshot.resolvedTopTaskTitle == nil {
            _ = await setNowPinned(false)
            return
        }
        _ = await LiveActivityManager.shared.refreshNowPin(from: snapshot)
    }

    private var pinRefreshTask: Task<Void, Never>?

    private func schedulePinRefresh(snapshot: WidgetSnapshot) {
        pinRefreshTask?.cancel()
        pinRefreshTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            if snapshot.resolvedTopTaskTitle == nil {
                _ = await setNowPinned(false)
                return
            }
            let result = await LiveActivityManager.shared.refreshNowPin(from: snapshot)
            if let title = snapshot.resolvedTopTaskTitle {
                PinNowLogger.info("sync refreshed pin for \"\(title)\" — \(result.message)")
            }
        }
    }

    func syncFocusActivity(adhdVM: ADHDViewModel) {
        guard !UITestLaunchConfiguration.shouldSkipLiveActivity else { return }
        Task { @MainActor in
            await Task.yield()
            guard adhdVM.isFocusSessionActive else {
                LiveActivityManager.shared.endFocusActivity()
                return
            }

            let taskTitle = adhdVM.currentFocusTask?.title ?? "Working"
            let remaining = max(0, adhdVM.focusSessionTarget - adhdVM.focusSessionElapsed)
            let endDate = Date().addingTimeInterval(remaining)

            LiveActivityManager.shared.updateFocusActivity(
                taskTitle: taskTitle,
                sessionNumber: adhdVM.currentSessionNumber,
                sessionEndDate: endDate,
                isOnBreak: adhdVM.isOnBreak,
                sessionLabel: adhdVM.sessionLabel,
                remainingLabel: adhdVM.focusRemainingString,
                isPaused: adhdVM.isPaused,
                progressFraction: adhdVM.focusProgress
            )
        }
    }

    func startFocusActivity(adhdVM: ADHDViewModel) {
        guard !UITestLaunchConfiguration.shouldSkipLiveActivity else { return }
        Task { @MainActor in
            await Task.yield()
            guard adhdVM.isFocusSessionActive else { return }

            let taskTitle = adhdVM.currentFocusTask?.title ?? "Working"
            let remaining = max(0, adhdVM.focusSessionTarget - adhdVM.focusSessionElapsed)
            let endDate = Date().addingTimeInterval(remaining)

            LiveActivityManager.shared.startFocusActivity(
                taskTitle: taskTitle,
                sessionNumber: adhdVM.currentSessionNumber,
                sessionEndDate: endDate,
                isOnBreak: adhdVM.isOnBreak,
                sessionLabel: adhdVM.sessionLabel,
                remainingLabel: adhdVM.focusRemainingString,
                isPaused: adhdVM.isPaused,
                progressFraction: adhdVM.focusProgress
            )
        }
    }

    private func makeSnapshot(
        brainVM: BrainViewModel,
        taskStore: TaskStore,
        healthStore: HealthStore,
        scheduleTasks: [LifeTask]? = nil,
        timelineEvents: [LifeTimelineEvent]? = nil
    ) -> WidgetSnapshot {
        let surface = brainVM.flowSurface
        let snapshot = brainVM.cognitiveSnapshot
        let health = healthStore.latest ?? brainVM.healthSummary
        let taskSnapshot = taskStore.snapshot
        let activeTasks = taskSnapshot.active.filter { $0.status.isActive }
        let resolverTasks = scheduleTasks ?? activeTasks

        let widgetTasks = brainVM.topTasks.prefix(3).map { task in
            WidgetTaskItem(
                id: task.id,
                title: task.title,
                estimatedMinutes: task.estimatedMinutes,
                priorityLabel: task.priority.label
            )
        }

        let storeFallbackTasks = activeTasks
            .prefix(3)
            .map { task in
                WidgetTaskItem(
                    id: task.id,
                    title: task.title,
                    estimatedMinutes: task.estimatedMinutes,
                    priorityLabel: task.priority.label
                )
            }

        let mergedTasks = widgetTasks.isEmpty ? Array(storeFallbackTasks) : Array(widgetTasks)

        let pinModel = PinNowSnapshotBuilder.build(
            tasks: resolverTasks,
            flowSurface: surface,
            cognitiveSnapshot: snapshot,
            preferredTask: surface?.heroTask ?? brainVM.topTasks.first,
            timelineEvents: timelineEvents
        )

        let widgetRecommendation: String
        if let pinModel {
            widgetRecommendation = pinModel.contextLine
        } else if let surface, brainVM.isUsingFlowDirector {
            let briefing = surface.briefingText.isEmpty ? surface.greeting : surface.briefingText
            widgetRecommendation = briefing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Your next step is ready."
                : briefing
        } else {
            widgetRecommendation = brainVM.recommendation
        }

        return WidgetSnapshot(
            topTaskTitle: pinModel?.headline ?? mergedTasks.first?.title,
            topTaskMinutes: pinModel?.estimatedMinutes,
            energyScore: pinModel?.energyScore ?? Int((surface?.energyScore ?? snapshot?.energyScore ?? 0.5) * 100),
            energyLevel: pinModel?.energyLevel ?? snapshot?.energy.rawValue ?? EnergyLevel.moderate.rawValue,
            recommendation: widgetRecommendation,
            completedTodayCount: taskSnapshot.completedToday.count,
            activeTaskCount: activeTasks.count,
            sleepHours: health?.totalSleepMinutes.map { $0 / 60 },
            stepCount: health?.stepCount,
            hrvMs: health?.hrvAverage.map { Int($0) },
            tasks: mergedTasks,
            updatedAt: Date(),
            pinContextLine: pinModel?.contextLine ?? "",
            pinScheduleLabel: pinModel?.scheduleLabel ?? "",
            pinConstraintLabel: pinModel?.constraintLabel ?? "Flexible",
            pinCategoryIcon: pinModel?.categoryIcon ?? "sparkles",
            pinNextUpSummary: pinModel?.nextUpSummary ?? "",
            pinProgressFraction: pinModel?.progressFraction ?? 0,
            pinSectionLabel: pinModel?.sectionLabel ?? "NOW"
        )
    }
}
