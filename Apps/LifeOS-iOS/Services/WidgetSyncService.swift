import Foundation
import WidgetKit
import LifeOSCore
import LifeOSData
import LifeOSFeatures

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
    
    func sync(brainVM: BrainViewModel, tasksVM: TasksViewModel) {
        let snapshot = makeSnapshot(brainVM: brainVM, tasksVM: tasksVM)
        WidgetDataStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        
        if isNowPinned {
            if snapshot.topTaskTitle != nil {
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
    
    func syncFocusActivity(adhdVM: ADHDViewModel) {
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
    
    func startFocusActivity(adhdVM: ADHDViewModel) {
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
    
    private func makeSnapshot(brainVM: BrainViewModel, tasksVM: TasksViewModel) -> WidgetSnapshot {
        let surface = brainVM.flowSurface
        let topTask = surface?.heroTask ?? brainVM.topTasks.first
        let snapshot = brainVM.cognitiveSnapshot
        let health = brainVM.healthSummary

        let recommendation: String
        if let surface, brainVM.isUsingFlowDirector {
            recommendation = surface.briefingText.isEmpty ? surface.greeting : surface.briefingText
        } else {
            recommendation = brainVM.recommendation
        }

        let widgetTasks = brainVM.topTasks.prefix(3).map { task in
            WidgetTaskItem(
                id: task.id,
                title: task.title,
                estimatedMinutes: task.estimatedMinutes,
                priorityLabel: task.priority.label
            )
        }

        return WidgetSnapshot(
            topTaskTitle: topTask?.title,
            topTaskMinutes: surface?.prediction?.suggestedDurationMinutes ?? topTask?.estimatedMinutes,
            energyScore: Int((surface?.energyScore ?? snapshot?.energyScore ?? 0.5) * 100),
            energyLevel: snapshot?.energy.rawValue ?? EnergyLevel.moderate.rawValue,
            recommendation: recommendation,
            completedTodayCount: tasksVM.completedToday.count,
            activeTaskCount: tasksVM.tasks.filter { $0.status.isActive }.count,
            sleepHours: health?.totalSleepMinutes.map { $0 / 60 },
            stepCount: health?.stepCount,
            hrvMs: health?.hrvAverage.map { Int($0) },
            tasks: Array(widgetTasks),
            updatedAt: Date()
        )
    }
}
