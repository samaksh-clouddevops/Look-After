import Foundation

/// Immutable view of director input used by scheduling rules.
/// Derived once per scheduling pass for deterministic rule evaluation.
public struct FlowSchedulingContext: Sendable {
    public let input: FlowDirectorInput
    public let calendar: Calendar

    public init(input: FlowDirectorInput, calendar: Calendar = .current) {
        self.input = input
        self.calendar = calendar
    }

    // MARK: - Derived Signals

    public var currentTime: Date { input.currentTime }
    public var environment: EnvironmentContext { input.environmentContext }
    public var behaviorMemory: BehaviorMemorySnapshot { input.behaviorMemory }

    public var energyScore: Double { environment.energyScore }
    public var focusReadiness: Double { input.cognitiveSnapshot.focusCapacity }

    /// Active tasks eligible for hero selection.
    public var activeTasks: [LifeTask] {
        input.pendingTasks.filter { $0.status.isActive }
    }

    public var inProgressTask: LifeTask? {
        activeTasks.first { $0.status == .inProgress }
    }

    public var nextCalendarEvent: CalendarEventReference? {
        environment.nextEvent ?? input.calendarEvents.first
    }

    public var freeBlockMinutes: Int { environment.freeBlockMinutes }

    public var flowWindow: DateInterval? { environment.flowWindow }

    public func deferralCount(for taskID: String) -> Int {
        behaviorMemory.deferralCount(for: taskID)
    }

    /// Rough sleep hours for semantic scheduling when precise HealthKit data isn't on this path.
    public var estimatedSleepHours: Double? {
        switch environment.sleepQuality {
        case .poor: return 5.0
        case .fair: return 6.5
        case .good, .excellent: return 7.5
        case .unknown: return nil
        }
    }

    /// Active tasks eligible for hero selection — respects schedule windows and recurrence.
    public func heroEligibleTasks(allTasks: [LifeTask]? = nil) -> [LifeTask] {
        let pool = allTasks ?? activeTasks
        return activeTasks.filter { task in
            TaskHeroEligibility.isEligible(
                for: task,
                now: currentTime,
                calendar: calendar,
                allTasks: pool
            )
        }
    }

    public var semanticSchedulerContext: TaskSemanticScheduler.Context {
        TaskSemanticScheduler.Context(
            now: currentTime,
            energyScore: energyScore,
            sleepHours: estimatedSleepHours,
            freeBlockMinutes: freeBlockMinutes,
            calendar: calendar
        )
    }
}
