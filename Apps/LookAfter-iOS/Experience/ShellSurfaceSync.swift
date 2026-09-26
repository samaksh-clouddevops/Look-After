import Foundation
import LookAfterCore
import LookAfterData
import LookAfterFeatures

/// Owns timeline rebuild debounce + widget / Live Activity / Focus Filter sync.
/// Extracted from `AppShellState` so the shell stays an orchestration façade (Q3).
@MainActor
final class ShellSurfaceSync {
    private let timelineService: TimelineService
    private let tasksVM: TasksViewModel
    private let modulesVM: LifeModulesViewModel
    private let brainVM: BrainViewModel
    private let taskStore: TaskStore
    private let healthStore: HealthStore
    private let adhdVM: ADHDViewModel
    private let calendarSyncService: CalendarSyncService

    private var timelineRebuildTask: Task<Void, Never>?
    private var syncWidgetsAfterDebouncedRebuild = false
    private static let timelineRebuildDebounceNs: UInt64 = 75_000_000

    var onPendingCalendarChange: ((CalendarChangeResult?) -> Void)?
    /// Fired with today's all-day event titles (holidays, PTO, etc.) after each rebuild —
    /// these are never turned into timeline rows/tasks, only surfaced as a greeting.
    var onHolidayNamesUpdated: (([String]) -> Void)?

    init(
        timelineService: TimelineService,
        tasksVM: TasksViewModel,
        modulesVM: LifeModulesViewModel,
        brainVM: BrainViewModel,
        taskStore: TaskStore,
        healthStore: HealthStore,
        adhdVM: ADHDViewModel,
        calendarSyncService: CalendarSyncService
    ) {
        self.timelineService = timelineService
        self.tasksVM = tasksVM
        self.modulesVM = modulesVM
        self.brainVM = brainVM
        self.taskStore = taskStore
        self.healthStore = healthStore
        self.adhdVM = adhdVM
        self.calendarSyncService = calendarSyncService
    }

    func resetDebounceState() {
        timelineRebuildTask?.cancel()
        timelineRebuildTask = nil
        syncWidgetsAfterDebouncedRebuild = false
    }

    func rebuildTimelineFromTasks(immediate: Bool = false) {
        if immediate {
            timelineRebuildTask?.cancel()
            timelineRebuildTask = nil
            performTimelineRebuild()
            return
        }
        timelineRebuildTask?.cancel()
        timelineRebuildTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.timelineRebuildDebounceNs)
            guard !Task.isCancelled, let self else { return }
            self.performTimelineRebuild()
            if self.syncWidgetsAfterDebouncedRebuild {
                self.syncWidgetsAfterDebouncedRebuild = false
                self.syncWidgetDataOnly()
                self.syncExecutionEnvironment()
            }
            self.timelineRebuildTask = nil
        }
    }

    func refreshWidgetData(rebuildTimeline: Bool = true, immediateTimelineRebuild: Bool = false) {
        if rebuildTimeline {
            if immediateTimelineRebuild {
                rebuildTimelineFromTasks(immediate: true)
                syncWidgetDataOnly(force: true)
                syncExecutionEnvironment()
            } else {
                syncWidgetsAfterDebouncedRebuild = true
                rebuildTimelineFromTasks(immediate: false)
            }
        } else {
            syncWidgetDataOnly()
            syncExecutionEnvironment()
        }
    }

    func syncWidgetDataOnly(force: Bool = false) {
        let scheduleTasks = plateScheduleTasks()
        WidgetSyncService.shared.sync(
            brainVM: brainVM,
            taskStore: taskStore,
            healthStore: healthStore,
            scheduleTasks: scheduleTasks,
            timelineEvents: timelineService.snapshot.today,
            force: force
        )
    }

    func refreshPinNow() {
        guard WidgetSyncService.shared.isNowPinned else { return }
        rebuildTimelineFromTasks(immediate: true)
        let scheduleTasks = plateScheduleTasks()
        Task {
            await WidgetSyncService.shared.refreshPinNow(
                brainVM: brainVM,
                taskStore: taskStore,
                healthStore: healthStore,
                scheduleTasks: scheduleTasks,
                timelineEvents: timelineService.snapshot.today
            )
        }
    }

    func startExecutionEnvironment() {
        let coordinator = ExecutionEnvironmentCoordinator.shared
        coordinator.onPinRefreshNeeded = { [weak self] in
            self?.refreshPinNow()
        }
        coordinator.setManualFocusActive(adhdVM.isFocusSessionActive)
        coordinator.updateTasks(plateScheduleTasks())
        coordinator.start()
    }

    func syncExecutionEnvironment() {
        let coordinator = ExecutionEnvironmentCoordinator.shared
        coordinator.setManualFocusActive(adhdVM.isFocusSessionActive)
        coordinator.updateTasks(plateScheduleTasks())
        coordinator.refresh()
    }

    func prepareExecutionEnvironmentForBackground() {
        let coordinator = ExecutionEnvironmentCoordinator.shared
        coordinator.setManualFocusActive(adhdVM.isFocusSessionActive)
        coordinator.updateTasks(plateScheduleTasks())
        coordinator.prepareForBackground()
    }

    func stopExecutionEnvironment() {
        ExecutionEnvironmentCoordinator.shared.stop()
    }

    /// Active + completed-today from the full plate (not list-snapshot alone).
    private func plateScheduleTasks() -> [LifeTask] {
        let userId = FirebaseManager.shared.resolvedUserId
        let allTasks = userId.isEmpty
            ? (tasksVM.tasks + tasksVM.completedToday + tasksVM.recurrenceTemplates)
            : tasksVM.localAllTasks(userId: userId)
        let plate = DayPlateBuilder.inputs(from: allTasks)
        return plate.tasks + plate.completedToday
    }

    private func performTimelineRebuild() {
        let calendar = Calendar.current
        let now = Date()
        let todayEvents = calendarSyncService.briefingEvents(on: now, calendar: calendar)
        let tomorrowEvents: [BriefingCalendarEvent]
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            tomorrowEvents = calendarSyncService.briefingEvents(on: tomorrow, calendar: calendar)
        } else {
            tomorrowEvents = []
        }
        // Full on-device plate — not the today-sliced TaskListSnapshot.active pool.
        let userId = FirebaseManager.shared.resolvedUserId
        let allTasks = userId.isEmpty ? (tasksVM.tasks + tasksVM.completedToday + tasksVM.recurrenceTemplates) : tasksVM.localAllTasks(userId: userId)
        let plate = DayPlateBuilder.inputs(from: allTasks, now: now, calendar: calendar)
        timelineService.rebuild(
            tasks: plate.tasks,
            completedToday: plate.completedToday,
            recurrenceTemplates: plate.recurrenceTemplates,
            bills: modulesVM.bills,
            shoppingItems: modulesVM.shoppingItems,
            contacts: modulesVM.contacts,
            medications: MedicationStore.resetDailyIfNeeded(),
            calendarEvents: todayEvents,
            tomorrowCalendarEvents: tomorrowEvents,
            now: now,
            calendar: calendar
        )
        if let change = CalendarChangeDetector.evaluate(timelineEvents: timelineService.snapshot.today) {
            onPendingCalendarChange?(change)
        }
        let holidayNames = todayEvents
            .filter(\.isAllDay)
            .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        onHolidayNamesUpdated?(holidayNames)
    }
}
