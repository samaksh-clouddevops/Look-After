import Foundation
import WidgetKit
import EventKit
import LookAfterCore
import LookAfterData
import LookAfterFeatures

/// Builds widget snapshot from app state and refreshes home screen + pinned Live Activity.
@MainActor
final class WidgetSyncService {

    static let shared = WidgetSyncService()

    private let pinNowKey = "pinNowToLockScreen"
    private let eventStore = EKEventStore()

    private init() {}

    var isNowPinned: Bool {
        UserDefaults.standard.bool(forKey: pinNowKey)
    }

    func setNowPinned(_ pinned: Bool) {
        UserDefaults.standard.set(pinned, forKey: pinNowKey)
        if pinned {
            let snapshot = WidgetDataStore.load()
            if snapshot.topTaskTitle != nil || snapshot.executive?.title != nil {
                LiveActivityManager.shared.startNowPin(from: snapshot)
            }
        } else {
            LiveActivityManager.shared.endNowPin()
        }
    }

    /// Auto-unpin Now Pin when the pinned hero task completes.
    func handleTaskCompleted(taskID: String) {
        guard isNowPinned else { return }
        let snap = WidgetDataStore.load()
        let pinnedID = snap.executive?.taskID
        if pinnedID == taskID || snap.topTaskTitle != nil {
            // If completed task was the hero, drop pin.
            if pinnedID == taskID {
                setNowPinned(false)
            }
        }
    }

    func sync(brainVM: BrainViewModel, tasksVM: TasksViewModel, adhdVM: ADHDViewModel? = nil) {
        let snapshot = makeSnapshot(brainVM: brainVM, tasksVM: tasksVM, adhdVM: adhdVM)
        WidgetDataStore.save(snapshot)
        reloadWidgetTimelines()

        if isNowPinned {
            let hasHero = (snapshot.executive?.taskID != nil) || (snapshot.topTaskTitle != nil)
            if hasHero {
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
            LookAfterWidgetKind.medication
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
        let hasHealth = health != nil && (
            (health?.totalSleepMinutes ?? 0) > 0
            || (health?.stepCount ?? 0) > 0
            || health?.hrvAverage != nil
        )
        let recovery = hasHealth
            ? (presentation.capacity.sleepLabel
                ?? health?.totalSleepMinutes.map { mins -> String in
                    let h = mins / 60
                    if h >= 7 { return "Good recovery" }
                    if h >= 5.5 { return "Fair recovery" }
                    return "Protect rest"
                })
            : nil
        let hydration = WidgetCommandProcessor.todayHydrationMl()

        return WidgetSnapshot(
            topTaskTitle: topTask?.title,
            topTaskMinutes: minutes,
            energyScore: energyScore,
            energyLevel: energyLevel,
            recommendation: whyLine,
            completedTodayCount: tasksVM.completedToday.count,
            activeTaskCount: tasksVM.tasks.filter(\.status.isActive).count,
            sleepHours: hasHealth ? health?.totalSleepMinutes.map { $0 / 60 } : nil,
            stepCount: hasHealth ? health?.stepCount : nil,
            hrvMs: hasHealth ? health?.hrvAverage.map { Int($0) } : nil,
            tasks: Array(widgetTasks),
            updatedAt: Date(),
            executive: executive,
            today: todaySummary,
            focus: focusState,
            medication: medStatus,
            recoveryLabel: recovery,
            hydrationMlToday: hydration > 0 ? hydration : nil,
            hasHealthData: hasHealth,
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
        let now = Date()

        // Calendar events (EventKit) — only if already authorized (no prompt from widget sync).
        let calendarBeats = loadCalendarBeats(from: now, formatter: timeFormatter)
        let nextCalendar = calendarBeats.first

        // Tasks with scheduled times
        var taskBeats: [WidgetTimelineBeat] = []
        let timedTasks = active
            .compactMap { task -> (LifeTask, Date)? in
                guard let t = task.scheduledTime, t >= now else { return nil }
                return (task, t)
            }
            .sorted { $0.1 < $1.1 }

        for (task, time) in timedTasks.prefix(4) {
            taskBeats.append(WidgetTimelineBeat(
                id: task.id,
                timeLabel: timeFormatter.string(from: time),
                title: task.title,
                detail: "\(task.estimatedMinutes)m",
                kind: "task"
            ))
        }

        // Merge calendar + tasks by time label order (simple stable merge via start times)
        var merged: [(sort: Date, beat: WidgetTimelineBeat)] = []
        for beat in calendarBeats {
            if let d = parseTimeToday(beat.timeLabel, formatter: timeFormatter) {
                merged.append((d, beat))
            }
        }
        for (task, time) in timedTasks.prefix(4) {
            merged.append((time, WidgetTimelineBeat(
                id: task.id,
                timeLabel: timeFormatter.string(from: time),
                title: task.title,
                detail: "\(task.estimatedMinutes)m",
                kind: "task"
            )))
        }
        merged.sort { $0.sort < $1.sort }
        var beats = merged.map(\.beat)
        // Deduplicate IDs keep first
        var seen = Set<String>()
        beats = beats.filter { seen.insert($0.id).inserted }
        beats = Array(beats.prefix(4))

        let free = brainVM.cognitiveSnapshot?.availableMinutes

        return WidgetTodaySummary(
            nextEventTitle: nextCalendar?.title ?? timedTasks.first?.0.title,
            nextEventTimeLabel: nextCalendar?.timeLabel ?? timedTasks.first.map { timeFormatter.string(from: $0.1) },
            nextTaskTitle: topTask?.title ?? active.first?.title,
            freeMinutes: free,
            capacityLabel: brainVM.presentation.capacity.bandLabel,
            beats: beats
        )
    }

    private func loadCalendarBeats(from date: Date, formatter: DateFormatter) -> [WidgetTimelineBeat] {
        let status = EKEventStore.authorizationStatus(for: .event)
        // iOS 17+: fullAccess / writeOnly. Do not prompt from widget sync.
        let authorized = status == .fullAccess || status == .writeOnly
        guard authorized else { return [] }

        let end = Calendar.current.date(byAdding: .hour, value: 12, to: date) ?? date.addingTimeInterval(12 * 3600)
        let predicate = eventStore.predicateForEvents(withStart: date, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .prefix(4)

        return events.map { ek in
            let mins = max(1, Int(ek.endDate.timeIntervalSince(ek.startDate) / 60))
            return WidgetTimelineBeat(
                id: ek.eventIdentifier ?? UUID().uuidString,
                timeLabel: formatter.string(from: ek.startDate),
                title: ek.title ?? "Event",
                detail: "\(mins)m",
                kind: "meeting"
            )
        }
    }

    private func parseTimeToday(_ label: String, formatter: DateFormatter) -> Date? {
        guard let t = formatter.date(from: label) else { return nil }
        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        let tc = cal.dateComponents([.hour, .minute], from: t)
        comps.hour = tc.hour
        comps.minute = tc.minute
        return cal.date(from: comps)
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
