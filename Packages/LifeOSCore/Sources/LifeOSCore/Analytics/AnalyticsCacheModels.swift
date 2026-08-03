import Foundation

/// Precomputed metrics for a single calendar day — the incremental analytics unit.
public struct AnalyticsDailySnapshot: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var date: Date
    public var userId: String
    public var sleepHours: Double?
    public var steps: Int?
    public var hrv: Double?
    public var restingHR: Double?
    public var energyScore: Double?
    public var efScore: Int?
    public var tasksCompleted: Int
    public var focusMinutes: Int
    public var focusSessions: Int
    public var habitCompletions: Int
    public var lastUpdated: Date

    public init(
        id: String,
        date: Date,
        userId: String,
        sleepHours: Double? = nil,
        steps: Int? = nil,
        hrv: Double? = nil,
        restingHR: Double? = nil,
        energyScore: Double? = nil,
        efScore: Int? = nil,
        tasksCompleted: Int = 0,
        focusMinutes: Int = 0,
        focusSessions: Int = 0,
        habitCompletions: Int = 0,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.userId = userId
        self.sleepHours = sleepHours
        self.steps = steps
        self.hrv = hrv
        self.restingHR = restingHR
        self.energyScore = energyScore
        self.efScore = efScore
        self.tasksCompleted = tasksCompleted
        self.focusMinutes = focusMinutes
        self.focusSessions = focusSessions
        self.habitCompletions = habitCompletions
        self.lastUpdated = lastUpdated
    }

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: date)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: day)
    }
}

/// Tracks what has been processed so refreshes can be incremental.
public struct AnalyticsCacheState: Codable, Sendable, Equatable {
    public var userId: String
    public var lastRefreshAt: Date?
    public var lastHealthSyncAt: Date?
    public var lastTaskChangeAt: Date?
    public var lastHabitChangeAt: Date?
    public var taskCountFingerprint: Int
    public var healthCountFingerprint: Int
    public var behaviorEventFingerprint: Int
    public var processedDayKeys: [String]

    public init(
        userId: String = "",
        lastRefreshAt: Date? = nil,
        lastHealthSyncAt: Date? = nil,
        lastTaskChangeAt: Date? = nil,
        lastHabitChangeAt: Date? = nil,
        taskCountFingerprint: Int = 0,
        healthCountFingerprint: Int = 0,
        behaviorEventFingerprint: Int = 0,
        processedDayKeys: [String] = []
    ) {
        self.userId = userId
        self.lastRefreshAt = lastRefreshAt
        self.lastHealthSyncAt = lastHealthSyncAt
        self.lastTaskChangeAt = lastTaskChangeAt
        self.lastHabitChangeAt = lastHabitChangeAt
        self.taskCountFingerprint = taskCountFingerprint
        self.healthCountFingerprint = healthCountFingerprint
        self.behaviorEventFingerprint = behaviorEventFingerprint
        self.processedDayKeys = processedDayKeys
    }
}

/// Compact cached summary fed to AI coach / personalization (never raw HealthKit dumps).
public struct CachedAIContextSummary: Codable, Sendable, Equatable {
    public var sleepAverage: Double?
    public var sleepTrend: String?
    public var energyScore: Int?
    public var stepsToday: Int?
    public var weeklyTaskCompletion: Int?
    public var deepWorkHours: Double?
    public var workoutStreak: Int?
    public var habitAdherencePercent: Int?
    public var peakProductivityWindow: String?
    public var generatedAt: Date
    public var isStale: Bool

    public init(
        sleepAverage: Double? = nil,
        sleepTrend: String? = nil,
        energyScore: Int? = nil,
        stepsToday: Int? = nil,
        weeklyTaskCompletion: Int? = nil,
        deepWorkHours: Double? = nil,
        workoutStreak: Int? = nil,
        habitAdherencePercent: Int? = nil,
        peakProductivityWindow: String? = nil,
        generatedAt: Date = Date(),
        isStale: Bool = false
    ) {
        self.sleepAverage = sleepAverage
        self.sleepTrend = sleepTrend
        self.energyScore = energyScore
        self.stepsToday = stepsToday
        self.weeklyTaskCompletion = weeklyTaskCompletion
        self.deepWorkHours = deepWorkHours
        self.workoutStreak = workoutStreak
        self.habitAdherencePercent = habitAdherencePercent
        self.peakProductivityWindow = peakProductivityWindow
        self.generatedAt = generatedAt
        self.isStale = isStale
    }

    /// Human-readable block for coach / planning personalization.
    public var promptBlock: String {
        var lines: [String] = []
        if let sleepAverage {
            lines.append("Average sleep: \(String(format: "%.1f", sleepAverage)) hours/night")
        }
        if let sleepTrend, !sleepTrend.isEmpty {
            lines.append("Sleep trend: \(sleepTrend)")
        }
        if let energyScore {
            lines.append("Recent energy score: \(energyScore)/100")
        }
        if let stepsToday {
            lines.append("Steps today: \(stepsToday)")
        }
        if let weeklyTaskCompletion {
            lines.append("Weekly task completion rate: \(weeklyTaskCompletion)%")
        }
        if let deepWorkHours {
            lines.append("Deep work this week: \(String(format: "%.1f", deepWorkHours)) hours")
        }
        if let workoutStreak, workoutStreak > 0 {
            lines.append("Workout streak: \(workoutStreak) days")
        }
        if let habitAdherencePercent {
            lines.append("Habit adherence: \(habitAdherencePercent)%")
        }
        if let peakProductivityWindow, !peakProductivityWindow.isEmpty {
            lines.append("Peak productivity window: \(peakProductivityWindow)")
        }
        if isStale {
            lines.append("Note: offline cached snapshot — treat as approximate")
        }
        guard !lines.isEmpty else { return "" }
        return "BEHAVIORAL ANALYTICS:\n" + lines.map { "- \($0)" }.joined(separator: "\n")
    }
}

public enum AnalyticsRefreshTrigger: String, Codable, Sendable {
    case appLaunch
    case appBackground
    case healthSyncCompleted
    case taskCompleted
    case habitChanged
    case insightsOpened
    case briefingOpened
    case manual
    case scheduled
}

public struct AnalyticsCacheBundle: Codable, Sendable {
    public var state: AnalyticsCacheState
    public var snapshots: [AnalyticsDailySnapshot]
    public var reports: [String: PersonalAnalyticsReport]
    public var aiContext: CachedAIContextSummary?

    public init(
        state: AnalyticsCacheState = AnalyticsCacheState(),
        snapshots: [AnalyticsDailySnapshot] = [],
        reports: [String: PersonalAnalyticsReport] = [:],
        aiContext: CachedAIContextSummary? = nil
    ) {
        self.state = state
        self.snapshots = snapshots
        self.reports = reports
        self.aiContext = aiContext
    }
}
