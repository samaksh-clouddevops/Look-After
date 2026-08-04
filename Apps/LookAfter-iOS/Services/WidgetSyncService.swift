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
    
    private init() {}
    
    var isNowPinned: Bool {
        UserDefaults.standard.bool(forKey: pinNowKey)
    }
    
    func setNowPinned(_ pinned: Bool) {
        UserDefaults.standard.set(pinned, forKey: pinNowKey)
        if pinned {
            let snapshot = WidgetDataStore.load()
            if snapshot.topTaskTitle != nil {
                LiveActivityManager.shared.startNowPin(from: snapshot)
            }
        } else {
            LiveActivityManager.shared.endNowPin()
        }
    }
    
    func sync(brainVM: BrainViewModel, tasksVM: TasksViewModel, adhdVM: ADHDViewModel? = nil) {
        let snapshot = makeSnapshot(brainVM: brainVM, tasksVM: tasksVM, adhdVM: adhdVM)
        WidgetDataStore.save(snapshot)
        reloadWidgetTimelines()

        if isNowPinned {
            if snapshot.topTaskTitle != nil || snapshot.executive != nil {
                if LiveActivityManager.shared.isNowPinned {
                    LiveActivityManager.shared.updateNowPin(from: snapshot)
                } else {
                    LiveActivityManager.shared.startNowPin(from: snapshot)
                }
            } else {
                setNowPinned(false)
            }
        }
    }

    /// Prefer kind-scoped reloads over reloadAllTimelines for battery + WidgetKit etiquette.
    private func reloadWidgetTimelines() {
        let kinds = [
            LookAfterWidgetKind.recommendation,
            LookAfterWidgetKind.today,
            LookAfterWidgetKind.focus,
            LookAfterWidgetKind.health,
            LookAfterWidgetKind.capture,
            LookAfterWidgetKind.nowV1,
            LookAfterWidgetKind.energyV1,
            LookAfterWidgetKind.tasksV1
        ]
        for kind in kinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
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
                isPaused: adhdVM.isPaused
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
                isPaused: adhdVM.isPaused
            )
        }
    }
    
    private func makeSnapshot(
        brainVM: BrainViewModel,
        tasksVM: TasksViewModel,
        adhdVM: ADHDViewModel?
    ) -> WidgetSnapshot {
        let surface = brainVM.flowSurface
        let topTask = surface?.heroTask ?? brainVM.topTasks.first
        let cognitive = brainVM.cognitiveSnapshot
        let health = brainVM.healthSummary
        let presentation = brainVM.presentation

        let whyLine: String
        if let surface, brainVM.isUsingFlowDirector {
            whyLine = surface.briefingText.isEmpty ? surface.greeting : surface.briefingText
        } else if let reasons = presentation.hero?.whyReasons, let first = reasons.first {
            whyLine = first
        } else {
            whyLine = brainVM.recommendation
        }

        let energyScore = Int((surface?.energyScore ?? cognitive?.energyScore ?? 0.5) * 100)
        let energyLevel = cognitive?.energy.rawValue ?? EnergyLevel.moderate.rawValue
        let minutes = surface?.prediction?.suggestedDurationMinutes ?? topTask?.estimatedMinutes

        let executive = WidgetRecommendation(
            taskID: topTask?.id,
            title: presentation.hero?.title ?? topTask?.title ?? WidgetRecommendation.clear.title,
            whyLine: whyLine,
            nextStepLine: presentation.hero?.supportingLine,
            estimatedMinutes: minutes,
            energyLabel: energyLevel,
            energyScore: energyScore
        )

        let widgetTasks = brainVM.topTasks.prefix(3).map { task in
            WidgetTaskItem(
                id: task.id,
                title: task.title,
                estimatedMinutes: task.estimatedMinutes,
                priorityLabel: task.priority.label
            )
        }

        let todaySummary = makeTodaySummary(tasksVM: tasksVM, brainVM: brainVM, topTask: topTask)
        let focusState = makeFocusState(adhdVM: adhdVM)
        let medStatus = makeMedicationStatus()
        let recovery = presentation.capacity.sleepLabel
            ?? health?.totalSleepMinutes.map { mins -> String in
                let h = mins / 60
                if h >= 7 { return "Good recovery" }
                if h >= 5.5 { return "Fair recovery" }
                return "Protect rest"
            }

        return WidgetSnapshot(
            topTaskTitle: topTask?.title,
            topTaskMinutes: minutes,
            energyScore: energyScore,
            energyLevel: energyLevel,
            recommendation: whyLine,
            completedTodayCount: tasksVM.completedToday.count,
            activeTaskCount: tasksVM.tasks.filter(\.status.isActive).count,
            sleepHours: health?.totalSleepMinutes.map { $0 / 60 },
            stepCount: health?.stepCount,
            hrvMs: health?.hrvAverage.map { Int($0) },
            tasks: Array(widgetTasks),
            updatedAt: Date(),
            executive: executive,
            today: todaySummary,
            focus: focusState,
            medication: medStatus,
            recoveryLabel: recovery,
            schemaVersion: 2
        )
    }

    private func makeTodaySummary(
        tasksVM: TasksViewModel,
        brainVM: BrainViewModel,
        topTask: LifeTask?
    ) -> WidgetTodaySummary {
        let active = tasksVM.tasks.filter(\.status.isActive)
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "H:mm"

        var beats: [WidgetTimelineBeat] = []
        for task in active.prefix(4) {
            let label: String
            if let t = task.scheduledTime {
                label = timeFormatter.string(from: t)
            } else {
                label = "Next"
            }
            beats.append(WidgetTimelineBeat(
                id: task.id,
                timeLabel: label,
                title: task.title,
                detail: "\(task.estimatedMinutes)m",
                kind: "task"
            ))
        }

        let nextTimed = active
            .compactMap { task -> (LifeTask, Date)? in
                guard let t = task.scheduledTime else { return nil }
                return (task, t)
            }
            .sorted { $0.1 < $1.1 }
            .first

        return WidgetTodaySummary(
            nextEventTitle: nextTimed?.0.title,
            nextEventTimeLabel: nextTimed.map { timeFormatter.string(from: $0.1) },
            nextTaskTitle: topTask?.title ?? active.first?.title,
            freeMinutes: brainVM.cognitiveSnapshot?.availableMinutes,
            capacityLabel: brainVM.presentation.capacity.bandLabel,
            beats: beats
        )
    }

    private func makeFocusState(adhdVM: ADHDViewModel?) -> WidgetFocusState {
        guard let adhdVM, adhdVM.isFocusSessionActive else { return .idle }
        let remaining = max(0, adhdVM.focusSessionTarget - adhdVM.focusSessionElapsed)
        return WidgetFocusState(
            isActive: true,
            taskTitle: adhdVM.currentFocusTask?.title,
            remainingLabel: adhdVM.focusRemainingString,
            sessionEndDate: Date().addingTimeInterval(remaining),
            isPaused: adhdVM.isPaused,
            isOnBreak: adhdVM.isOnBreak
        )
    }

    private func makeMedicationStatus() -> WidgetMedicationStatus {
        let meds = MedicationStore.load()
        guard let next = meds.filter({ !$0.isTaken }).sorted(by: { $0.scheduledTime < $1.scheduledTime }).first
                ?? meds.sorted(by: { $0.scheduledTime < $1.scheduledTime }).first
        else {
            return .none
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return WidgetMedicationStatus(
            id: next.id,
            name: next.name,
            timeLabel: formatter.string(from: next.scheduledTime),
            isTaken: next.isTaken,
            dosage: next.dosage
        )
    }
}
