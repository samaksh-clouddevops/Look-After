import Foundation
import LookAfterCore
import LookAfterFeatures
import LookAfterData

/// Drains App Group widget commands into in-app state.
@MainActor
enum WidgetCommandProcessor {

    static func processPending(shell: AppShellState) async {
        let commands = WidgetCommandQueue.drain()
        guard !commands.isEmpty else { return }

        let userId = FirebaseManager.shared.resolvedUserId
        for command in commands {
            await apply(command, shell: shell, userId: userId)
        }
        shell.refreshWidgetData()
    }

    private static func apply(
        _ command: WidgetCommand,
        shell: AppShellState,
        userId: String
    ) async {
        switch command.kind {
        case .completeTask:
            guard let id = command.taskID,
                  let task = shell.tasksVM.tasks.first(where: { $0.id == id })
            else { return }
            _ = await shell.tasksVM.completeTask(task)
            if shell.adhdVM.currentFocusTask?.id == id {
                shell.adhdVM.endFocusSession()
            }
            WidgetSyncService.shared.handleTaskCompleted(taskID: id)

        case .snoozeTask:
            guard let id = command.taskID,
                  let task = shell.tasksVM.tasks.first(where: { $0.id == id })
            else { return }
            let minutes = command.snoozeMinutes ?? 60
            var updated = task
            let when = Date().addingTimeInterval(TimeInterval(minutes * 60))
            updated.scheduledTime = when
            updated.scheduledDate = Calendar.current.startOfDay(for: when)
            updated.updatedAt = Date()
            shell.tasksVM.updateTask(updated)
            await shell.brainVM.handleTaskDeferred(task, userId: userId)

        case .markMedicationTaken:
            guard let id = command.medicationID else { return }
            var meds = MedicationStore.load()
            guard let index = meds.firstIndex(where: { $0.id == id }) else { return }
            meds[index].isTaken = true
            meds[index].lastTakenAt = Date()
            meds[index].adherenceLog.append(Date())
            MedicationStore.save(meds)

        case .logWater:
            let amount = command.amountMl ?? 250
            logWater(amountMl: amount, userId: userId, shell: shell)

        case .startFocus:
            let task: LifeTask?
            if let id = command.taskID {
                task = shell.tasksVM.tasks.first(where: { $0.id == id })
                    ?? shell.brainVM.topTasks.first(where: { $0.id == id })
            } else {
                task = shell.brainVM.flowSurface?.heroTask ?? shell.brainVM.topTasks.first
            }
            if let task {
                shell.adhdVM.startFocusSession(task: task)
            }

        case .endFocus:
            shell.adhdVM.endFocusSession()

        case .pauseFocus:
            if shell.adhdVM.isPaused {
                shell.adhdVM.resumeFocusSession()
            } else if shell.adhdVM.isFocusSessionActive {
                shell.adhdVM.pauseFocusSession()
            }

        case .resumeFocus:
            shell.adhdVM.resumeFocusSession()
        }
    }

    private static func logWater(amountMl: Double, userId: String, shell: AppShellState) {
        // Persist via App Group snapshot patch + UserDefaults daily total for widgets.
        let key = "lookafter.hydration.ml.\(dayKey())"
        let defaults = UserDefaults(suiteName: WidgetAppGroup.identifier) ?? .standard
        let current = defaults.double(forKey: key)
        defaults.set(current + amountMl, forKey: key)
        // Also keep standard defaults for in-app mirrors if needed.
        UserDefaults.standard.set(defaults.double(forKey: key), forKey: key)
    }

    private static func dayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    static func todayHydrationMl() -> Double {
        let key = "lookafter.hydration.ml.\(dayKey())"
        let suite = UserDefaults(suiteName: WidgetAppGroup.identifier)?.double(forKey: key) ?? 0
        if suite > 0 { return suite }
        return UserDefaults.standard.double(forKey: key)
    }
}
