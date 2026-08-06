import Foundation
import LookAfterCore

// MARK: - Card catalog

public enum BriefingCardKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case greeting
    case executiveHero
    case healthSnapshot
    case dailySummary
    case sleep
    case energy
    case mission
    case calendar
    case health
    case habits
    case aiCoach
    case focusPrediction
    case progress
    case weeklyTrends
    case alerts
    case cycle

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .greeting: return "Greeting"
        case .executiveHero: return "For today"
        case .healthSnapshot: return "How you're doing"
        case .dailySummary: return "Day so far"
        case .sleep: return "Sleep"
        case .energy: return "Energy"
        case .mission: return UserFacingCopy.todayTitle
        case .calendar: return "Calendar"
        case .health: return "Health"
        case .habits: return "Habits"
        case .aiCoach: return UserFacingCopy.suggestedNextStepTitle
        case .focusPrediction: return UserFacingCopy.openWindowsTitle
        case .progress: return UserFacingCopy.progressTitle
        case .weeklyTrends: return "This week"
        case .alerts: return UserFacingCopy.headsUpTitle
        case .cycle: return "Cycle"
        }
    }

    public var icon: String {
        switch self {
        case .greeting: return "sun.max.fill"
        case .executiveHero: return "sparkles"
        case .healthSnapshot: return "heart.text.square.fill"
        case .dailySummary: return "chart.line.uptrend.xyaxis"
        case .sleep: return "bed.double.fill"
        case .energy: return "brain.head.profile"
        case .mission: return "target"
        case .calendar: return "calendar"
        case .health: return "heart.fill"
        case .habits: return "checkmark.circle.fill"
        case .aiCoach: return "sparkles"
        case .focusPrediction: return "brain.head.profile"
        case .progress: return "chart.bar.fill"
        case .weeklyTrends: return "waveform.path.ecg"
        case .alerts: return "bell.badge.fill"
        case .cycle: return "circle.circle.fill"
        }
    }

    /// Cards replaced by `.healthSnapshot` — kept for customization migration.
    public static let legacyMetricCards: Set<BriefingCardKind> = [.dailySummary, .sleep, .energy]

    public static var defaultOrder: [BriefingCardKind] {
        [
            .greeting,
            .executiveHero,
            .healthSnapshot,
            .aiCoach,
            .mission,
            .calendar,
            .alerts,
            .health,
            .cycle,
            .habits,
            .focusPrediction,
            .progress,
            .weeklyTrends,
        ]
    }
}

public enum BriefingLayoutMode: String, Codable, CaseIterable, Sendable {
    case detailed
    case compact

    public var label: String {
        switch self {
        case .detailed: return "Detailed"
        case .compact: return "Compact"
        }
    }
}

// MARK: - Presentation models

public struct BriefingGreeting: Sendable, Equatable {
    public var timeGreeting: String
    public var userName: String
    public var dateLine: String

    public init(timeGreeting: String, userName: String, dateLine: String) {
        self.timeGreeting = timeGreeting
        self.userName = userName
        self.dateLine = dateLine
    }
}

public struct BriefingDailySummary: Sendable, Equatable {
    public var score: Int
    public var maxScore: Int
    public var scoreLabel: String
    public var scoreBand: String
    public var narrative: String

    public init(
        score: Int,
        maxScore: Int = 100,
        scoreLabel: String = "",
        scoreBand: String = "",
        narrative: String = ""
    ) {
        self.score = score
        self.maxScore = maxScore
        self.scoreLabel = scoreLabel.isEmpty ? UserFacingCopy.readinessLabel(score: score) : scoreLabel
        self.scoreBand = scoreBand.isEmpty ? UserFacingCopy.readinessBand(score: score) : scoreBand
        self.narrative = narrative
    }
}

public struct BriefingExecutiveHero: Sendable, Equatable {
    public var greeting: String
    public var narrative: String
    public var actionLine: String
    public var whyLine: String?
    public var buttonLabel: String
    public var durationLabel: String?
    public var impactLabel: String?
    public var clarityLabel: String?
    public var ignoreConsequence: String?
    public var alternativeLabel: String?
    public var actionKind: ContextActionKind?
    public var actionTaskID: String?

    public var isActionableTask: Bool {
        guard let kind = actionKind else { return false }
        switch kind {
        case .openBrain, .viewPlan, .openCoach, .openHealthDetail, .openShopping:
            return false
        default:
            return true
        }
    }

    public init(
        greeting: String,
        narrative: String,
        actionLine: String,
        whyLine: String? = nil,
        buttonLabel: String,
        durationLabel: String? = nil,
        impactLabel: String? = nil,
        clarityLabel: String? = nil,
        ignoreConsequence: String? = nil,
        alternativeLabel: String? = nil,
        actionKind: ContextActionKind? = nil,
        actionTaskID: String? = nil
    ) {
        self.greeting = greeting
        self.narrative = narrative
        self.actionLine = actionLine
        self.whyLine = whyLine
        self.buttonLabel = buttonLabel
        self.durationLabel = durationLabel
        self.impactLabel = impactLabel
        self.clarityLabel = clarityLabel
        self.ignoreConsequence = ignoreConsequence
        self.alternativeLabel = alternativeLabel
        self.actionKind = actionKind
        self.actionTaskID = actionTaskID
    }
}

public struct BriefingHealthSnapshot: Sendable, Equatable {
    public var readinessLabel: String
    public var readinessScore: Int
    public var readinessBand: String
    public var sleepHours: String?
    public var sleepQuality: String?
    public var energyPercent: Int
    public var energyLevel: String
    public var recoveryLabel: String
    public var recoveryPercent: Int
    public var focusWindow: String
    public var isHealthConnected: Bool
    /// False when last night's sleep was not recorded — energy tile should show unavailable, not a guess.
    public var hasOvernightHealthSignal: Bool

    public init(
        readinessLabel: String,
        readinessScore: Int,
        readinessBand: String,
        sleepHours: String? = nil,
        sleepQuality: String? = nil,
        energyPercent: Int,
        energyLevel: String,
        recoveryLabel: String,
        recoveryPercent: Int = 50,
        focusWindow: String,
        isHealthConnected: Bool,
        hasOvernightHealthSignal: Bool = true
    ) {
        self.readinessLabel = readinessLabel
        self.readinessScore = readinessScore
        self.readinessBand = readinessBand
        self.sleepHours = sleepHours
        self.sleepQuality = sleepQuality
        self.energyPercent = energyPercent
        self.energyLevel = energyLevel
        self.recoveryLabel = recoveryLabel
        self.recoveryPercent = recoveryPercent
        self.focusWindow = focusWindow
        self.isHealthConnected = isHealthConnected
        self.hasOvernightHealthSignal = hasOvernightHealthSignal
    }
}

public struct BriefingSleepData: Sendable, Equatable {
    public var totalHours: Double?
    public var deepHours: Double?
    public var remHours: Double?
    public var qualityPercent: Int?
    public var sleepDebtHours: Double
    public var isAvailable: Bool

    public init(
        totalHours: Double? = nil,
        deepHours: Double? = nil,
        remHours: Double? = nil,
        qualityPercent: Int? = nil,
        sleepDebtHours: Double = 0,
        isAvailable: Bool = true
    ) {
        self.totalHours = totalHours
        self.deepHours = deepHours
        self.remHours = remHours
        self.qualityPercent = qualityPercent
        self.sleepDebtHours = sleepDebtHours
        self.isAvailable = isAvailable
    }
}

public struct BriefingEnergyData: Sendable, Equatable {
    public var currentEnergyPercent: Int
    public var peakFocusWindow: String
    public var afternoonDipWindow: String
    public var recoveryPercent: Int
    public var energyLevel: EnergyLevel

    public init(
        currentEnergyPercent: Int,
        peakFocusWindow: String,
        afternoonDipWindow: String,
        recoveryPercent: Int,
        energyLevel: EnergyLevel
    ) {
        self.currentEnergyPercent = currentEnergyPercent
        self.peakFocusWindow = peakFocusWindow
        self.afternoonDipWindow = afternoonDipWindow
        self.recoveryPercent = recoveryPercent
        self.energyLevel = energyLevel
    }
}

public struct BriefingMissionTask: Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var isCompleted: Bool
    public var priority: Priority

    public init(id: String, title: String, isCompleted: Bool, priority: Priority) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.priority = priority
    }
}

public struct BriefingMissionData: Sendable, Equatable {
    public var tasks: [BriefingMissionTask]
    public var completionPercent: Int

    public init(tasks: [BriefingMissionTask], completionPercent: Int) {
        self.tasks = tasks
        self.completionPercent = completionPercent
    }
}

public struct BriefingCalendarData: Sendable, Equatable {
    public var nextEventTitle: String?
    public var minutesUntilStart: Int?
    public var durationMinutes: Int?
    public var isConnected: Bool

    public init(
        nextEventTitle: String? = nil,
        minutesUntilStart: Int? = nil,
        durationMinutes: Int? = nil,
        isConnected: Bool = true
    ) {
        self.nextEventTitle = nextEventTitle
        self.minutesUntilStart = minutesUntilStart
        self.durationMinutes = durationMinutes
        self.isConnected = isConnected
    }
}

public struct BriefingHealthMetrics: Sendable, Equatable {
    public var steps: Int?
    public var moveRingPercent: Int?
    public var exerciseMinutes: Int?
    public var standHours: Int?
    public var restingHR: Int?
    public var hrv: Int?
    public var isAvailable: Bool

    public init(
        steps: Int? = nil,
        moveRingPercent: Int? = nil,
        exerciseMinutes: Int? = nil,
        standHours: Int? = nil,
        restingHR: Int? = nil,
        hrv: Int? = nil,
        isAvailable: Bool = true
    ) {
        self.steps = steps
        self.moveRingPercent = moveRingPercent
        self.exerciseMinutes = exerciseMinutes
        self.standHours = standHours
        self.restingHR = restingHR
        self.hrv = hrv
        self.isAvailable = isAvailable
    }
}

public struct BriefingHabit: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var icon: String
    public var isCompletedToday: Bool

    public init(id: String, title: String, icon: String, isCompletedToday: Bool = false) {
        self.id = id
        self.title = title
        self.icon = icon
        self.isCompletedToday = isCompletedToday
    }

    public static var defaults: [BriefingHabit] {
        [
            BriefingHabit(id: "water", title: "Water", icon: "drop.fill"),
            BriefingHabit(id: "medication", title: "Medication", icon: "pills.fill"),
            BriefingHabit(id: "protein", title: "Protein Goal", icon: "fork.knife"),
            BriefingHabit(id: "workout", title: "Workout", icon: "figure.run"),
            BriefingHabit(id: "reading", title: "Reading", icon: "book.fill"),
            BriefingHabit(id: "meditation", title: "Meditation", icon: "leaf.fill"),
        ]
    }
}

public struct BriefingFocusWindow: Identifiable, Sendable, Equatable {
    public var id: String
    public var label: String
    public var timeRange: String
    public var icon: String

    public init(id: String, label: String, timeRange: String, icon: String) {
        self.id = id
        self.label = label
        self.timeRange = timeRange
        self.icon = icon
    }
}

public struct BriefingProgressData: Sendable, Equatable {
    public var completedCount: Int
    public var remainingCount: Int
    public var overdueCount: Int
    public var deepWorkMinutes: Int
    public var productivityScore: Int

    public init(
        completedCount: Int,
        remainingCount: Int,
        overdueCount: Int,
        deepWorkMinutes: Int,
        productivityScore: Int
    ) {
        self.completedCount = completedCount
        self.remainingCount = remainingCount
        self.overdueCount = overdueCount
        self.deepWorkMinutes = deepWorkMinutes
        self.productivityScore = productivityScore
    }

    /// Full-day completion percentage (completed vs active workload).
    public var dayCompletionPercent: Int {
        let total = completedCount + remainingCount
        guard total > 0 else { return 0 }
        return Int((Double(completedCount) / Double(total)) * 100)
    }
}

public struct BriefingTrendPoint: Identifiable, Sendable, Equatable {
    public var id: String
    public var label: String
    public var value: Double

    public init(id: String, label: String, value: Double) {
        self.id = id
        self.label = label
        self.value = value
    }
}

public struct BriefingWeeklyTrends: Sendable, Equatable {
    public var sleep: [BriefingTrendPoint]
    public var energy: [BriefingTrendPoint]
    public var steps: [BriefingTrendPoint]
    public var taskCompletion: [BriefingTrendPoint]

    public init(
        sleep: [BriefingTrendPoint] = [],
        energy: [BriefingTrendPoint] = [],
        steps: [BriefingTrendPoint] = [],
        taskCompletion: [BriefingTrendPoint] = []
    ) {
        self.sleep = sleep
        self.energy = energy
        self.steps = steps
        self.taskCompletion = taskCompletion
    }
}

public enum BriefingAlertSeverity: Sendable, Equatable {
    case info
    case warning
    case urgent
}

public struct BriefingAlert: Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var message: String
    public var icon: String
    public var severity: BriefingAlertSeverity

    public init(id: String, title: String, message: String, icon: String, severity: BriefingAlertSeverity) {
        self.id = id
        self.title = title
        self.message = message
        self.icon = icon
        self.severity = severity
    }
}

public struct BriefingCycleData: Sendable, Equatable {
    public var snapshot: CycleSnapshot
    public var topInsight: CycleInsight?

    public static let disabled = BriefingCycleData(snapshot: .disabled, topInsight: nil)

    public var isVisible: Bool { CycleFeatureGate.isActive && snapshot.isEnabled }

    public init(snapshot: CycleSnapshot, topInsight: CycleInsight? = nil) {
        self.snapshot = snapshot
        self.topInsight = topInsight
    }
}

public struct BriefingModuleInsight: Identifiable, Sendable, Equatable {
    public var id: String
    public var module: String
    public var icon: String
    public var message: String

    public init(id: String = UUID().uuidString, module: String, icon: String, message: String) {
        self.id = id
        self.module = module
        self.icon = icon
        self.message = message
    }
}
