import Foundation
import LifeOSCore

/// Canonical continuously-updated model of the user's life.
/// One source of truth — UI reads this, never recomputes it.
public struct WorldState: Codable, Sendable, Equatable {
    public var generatedAt: Date

    // Energy & cognition
    public var currentEnergy: Double
    public var cognitiveLoad: CognitiveLoadLevel
    public var sleepHoursLastNight: Double?
    public var sleepQuality: SleepQuality
    public var healthReadiness: Double

    // Time & calendar
    public var availableMinutes: Int
    public var minutesUntilNextEvent: Int?
    public var nextEventTitle: String?
    public var isMeetingHeavyDay: Bool

    // Mission & work
    public var currentMission: LifeTask?
    public var topTasks: [LifeTask]
    public var upcomingDeadlines: [TaskDeadlineRef]
    public var lastWorkingContext: WorkingContext?

    // Life domains
    public var location: LocationContext
    public var medicationStatus: MedicationWorldStatus
    public var unpurchasedShoppingCount: Int
    public var unpaidBillsCount: Int
    public var isInFlowSession: Bool

    // Resume continuity
    public var resumeSnapshot: ResumeSnapshot?

    public init(
        generatedAt: Date = Date(),
        currentEnergy: Double = 0.5,
        cognitiveLoad: CognitiveLoadLevel = .moderate,
        sleepHoursLastNight: Double? = nil,
        sleepQuality: SleepQuality = .unknown,
        healthReadiness: Double = 0.5,
        availableMinutes: Int = 0,
        minutesUntilNextEvent: Int? = nil,
        nextEventTitle: String? = nil,
        isMeetingHeavyDay: Bool = false,
        currentMission: LifeTask? = nil,
        topTasks: [LifeTask] = [],
        upcomingDeadlines: [TaskDeadlineRef] = [],
        lastWorkingContext: WorkingContext? = nil,
        location: LocationContext = .unknown,
        medicationStatus: MedicationWorldStatus = .unknown,
        unpurchasedShoppingCount: Int = 0,
        unpaidBillsCount: Int = 0,
        isInFlowSession: Bool = false,
        resumeSnapshot: ResumeSnapshot? = nil
    ) {
        self.generatedAt = generatedAt
        self.currentEnergy = currentEnergy
        self.cognitiveLoad = cognitiveLoad
        self.sleepHoursLastNight = sleepHoursLastNight
        self.sleepQuality = sleepQuality
        self.healthReadiness = healthReadiness
        self.availableMinutes = availableMinutes
        self.minutesUntilNextEvent = minutesUntilNextEvent
        self.nextEventTitle = nextEventTitle
        self.isMeetingHeavyDay = isMeetingHeavyDay
        self.currentMission = currentMission
        self.topTasks = topTasks
        self.upcomingDeadlines = upcomingDeadlines
        self.lastWorkingContext = lastWorkingContext
        self.location = location
        self.medicationStatus = medicationStatus
        self.unpurchasedShoppingCount = unpurchasedShoppingCount
        self.unpaidBillsCount = unpaidBillsCount
        self.isInFlowSession = isInFlowSession
        self.resumeSnapshot = resumeSnapshot
    }
}

public enum CognitiveLoadLevel: String, Codable, Sendable {
    case low, moderate, high, overloaded
}

public struct TaskDeadlineRef: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var taskTitle: String
    public var deadline: Date
    public var daysRemaining: Int

    public init(id: String, taskTitle: String, deadline: Date, daysRemaining: Int) {
        self.id = id
        self.taskTitle = taskTitle
        self.deadline = deadline
        self.daysRemaining = daysRemaining
    }
}

/// Medication state derived from user-configured schedule — never inferred.
public enum MedicationWorldStatus: Codable, Sendable, Equatable {
    case unknown
    case noneConfigured
    case allTakenToday
    case dueNow(items: [MedicationDueItem])
    case missedToday(items: [MedicationDueItem])
    case upcoming(items: [MedicationDueItem])
}

public struct MedicationDueItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var dosage: String
    public var scheduledTimeLabel: String
    public var scheduledTime: Date
    public var isTaken: Bool

    public init(
        id: String,
        name: String,
        dosage: String,
        scheduledTimeLabel: String,
        scheduledTime: Date,
        isTaken: Bool
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.scheduledTimeLabel = scheduledTimeLabel
        self.scheduledTime = scheduledTime
        self.isTaken = isTaken
    }
}
