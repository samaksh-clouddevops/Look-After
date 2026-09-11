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
        WidgetSyncService.shared.sync(
            brainVM: brainVM,
            taskStore: taskStore,
            healthStore: healthStore,
            scheduleTasks: tasksVM.tasks + tasksVM.completedToday,
            timelineEvents: timelineService.snapshot.today,
            force: force
        )
    }

    func refreshPinNow() {
        guard WidgetSyncService.shared.isNowPinned else { return }
        rebuildTimelineFromTasks(immediate: true)
        Task {
            await WidgetSyncService.shared.refreshPinNow(
                brainVM: brainVM,
                taskStore: taskStore,
                healthStore: healthStore,
                scheduleTasks: tasksVM.tasks + tasksVM.completedToday,
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
        coordinator.updateTasks(tasksVM.tasks + tasksVM.completedToday)
        coordinator.start()
    }

    func syncExecutionEnvironment() {
        let coordinator = ExecutionEnvironmentCoordinator.shared
        coordinator.setManualFocusActive(adhdVM.isFocusSessionActive)
        coordinator.updateTasks(tasksVM.tasks + tasksVM.completedToday)
        coordinator.refresh()
    }

    func prepareExecutionEnvironmentForBackground() {
        let coordinator = ExecutionEnvironmentCoordinator.shared
        coordinator.setManualFocusActive(adhdVM.isFocusSessionActive)
        coordinator.updateTasks(tasksVM.tasks + tasksVM.completedToday)
        coordinator.prepareForBackground()
    }

    func stopExecutionEnvironment() {
        ExecutionEnvironmentCoordinator.shared.stop()
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
        timelineService.rebuild(
            tasks: tasksVM.tasks,
            completedToday: tasksVM.completedToday,
            recurrenceTemplates: tasksVM.recurrenceTemplates,
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
    }
}
