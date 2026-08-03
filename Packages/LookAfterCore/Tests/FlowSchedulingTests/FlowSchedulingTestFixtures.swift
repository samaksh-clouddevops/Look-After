import Foundation
@testable import LookAfterCore

enum FlowSchedulingTestFixtures {

    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    static var morningDate: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 31
        components.hour = 9
        components.minute = 0
        return calendar.date(from: components)!
    }

    static func task(
        id: String = UUID().uuidString,
        title: String,
        status: TaskStatus = .pending,
        estimatedMinutes: Int = 30,
        difficulty: TaskDifficulty = .medium,
        requiredEnergy: EnergyLevel = .moderate,
        priority: Priority = .medium
    ) -> LifeTask {
        LifeTask(
            id: id,
            title: title,
            priority: priority,
            difficulty: difficulty,
            status: status,
            estimatedMinutes: estimatedMinutes,
            requiredEnergy: requiredEnergy
        )
    }

    static func input(
        tasks: [LifeTask],
        environment: EnvironmentContext = EnvironmentContext(energyScore: 0.7, timeOfDay: .morning),
        behavior: BehaviorMemorySnapshot = .empty,
        session: FlowSessionState? = nil,
        at date: Date? = nil
    ) -> FlowDirectorInput {
        FlowDirectorInput(
            cognitiveSnapshot: CognitiveSnapshot(energyScore: environment.energyScore, focusCapacity: 0.7),
            pendingTasks: tasks,
            behaviorMemory: behavior,
            environmentContext: environment,
            activeFlowSession: session,
            currentTime: date ?? morningDate,
            userName: "Sam"
        )
    }

    static func context(from input: FlowDirectorInput) -> FlowSchedulingContext {
        FlowSchedulingContext(input: input, calendar: calendar)
    }
}
