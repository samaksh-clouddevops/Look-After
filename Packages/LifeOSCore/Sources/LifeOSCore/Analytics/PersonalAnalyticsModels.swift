import Foundation

// MARK: - Time ranges

public enum InsightsTimeframe: String, Codable, CaseIterable, Identifiable, Sendable {
    case today = "Today"
    case yesterday = "Yesterday"
    case last7Days = "Last 7 Days"
    case last30Days = "Last 30 Days"
    case last90Days = "Last 90 Days"
    case last6Months = "Last 6 Months"
    case lastYear = "Last Year"
    case allTime = "All Time"

    public var id: String { rawValue }

    public var dayCount: Int {
        switch self {
        case .today, .yesterday: return 1
        case .last7Days: return 7
        case .last30Days: return 30
        case .last90Days: return 90
        case .last6Months: return 180
        case .lastYear: return 365
        case .allTime: return 365 * 5
        }
    }

    public func dateRange(calendar: Calendar = .current, now: Date = Date()) -> (start: Date, end: Date) {
        let end = now
        switch self {
        case .today:
            return (calendar.startOfDay(for: now), end)
        case .yesterday:
            let day = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            let start = calendar.startOfDay(for: day)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: start) ?? end
            return (start, endOfDay)
        case .last7Days:
            let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
            return (start, end)
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now
            return (start, end)
        case .last90Days:
            let start = calendar.date(byAdding: .day, value: -89, to: calendar.startOfDay(for: now)) ?? now
            return (start, end)
        case .last6Months:
            let start = calendar.date(byAdding: .month, value: -6, to: calendar.startOfDay(for: now)) ?? now
            return (start, end)
        case .lastYear:
            let start = calendar.date(byAdding: .year, value: -1, to: calendar.startOfDay(for: now)) ?? now
            return (start, end)
        case .allTime:
            return (Date.distantPast, end)
        }
    }
}

// MARK: - Chart & insight models

public enum AnalyticsMetricKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case sleep
    case energy
    case steps
    case taskCompletion
    case focusSessions
    case habitCompletion
    case productivityScore
    case restingHeartRate
    case hrv

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sleep: return "Sleep"
        case .energy: return "Energy"
        case .steps: return "Steps"
        case .taskCompletion: return "Tasks Completed"
        case .focusSessions: return "Timer sessions"
        case .habitCompletion: return "Habits"
        case .productivityScore: return UserFacingCopy.dayScoreTitle
        case .restingHeartRate: return "Resting HR"
        case .hrv: return "HRV"
        }
    }
}

public struct AnalyticsTrendPoint: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var label: String
    public var value: Double
    public var date: Date?

    public init(id: String, label: String, value: Double, date: Date? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.date = date
    }
}

public struct AnalyticsChartSeries: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var metric: AnalyticsMetricKind
    public var points: [AnalyticsTrendPoint]
    public var unit: String
    public var hasData: Bool

    public init(
        id: String = UUID().uuidString,
        metric: AnalyticsMetricKind,
        points: [AnalyticsTrendPoint],
        unit: String = "",
        hasData: Bool = false
    ) {
        self.id = id
        self.metric = metric
        self.points = points
        self.unit = unit
        self.hasData = hasData
    }
}

public enum AnalyticsInsightCategory: String, Codable, Sendable {
    case sleep
    case energy
    case productivity
    case health
    case habits
    case correlation
    case coach
}

public struct AnalyticsInsight: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var category: AnalyticsInsightCategory
    public var message: String

    public init(id: String = UUID().uuidString, category: AnalyticsInsightCategory, message: String) {
        self.id = id
        self.category = category
        self.message = message
    }
}

public struct PersonalAnalyticsKPIs: Codable, Sendable, Equatable {
    public var totalFocusMinutes: Int?
    public var completedTasksCount: Int?
    public var averageEnergyScore: Double?
    public var averageExecutiveFunctionScore: Int?
    public var peakProductivityWindow: String?
    public var averageSleepHours: Double?
    public var averageSteps: Int?
    public var averageHRV: Double?
    public var habitAdherencePercent: Int?
    public var overdueTasksCount: Int?
    public var focusSessionCount: Int?

    public init(
        totalFocusMinutes: Int? = nil,
        completedTasksCount: Int? = nil,
        averageEnergyScore: Double? = nil,
        averageExecutiveFunctionScore: Int? = nil,
        peakProductivityWindow: String? = nil,
        averageSleepHours: Double? = nil,
        averageSteps: Int? = nil,
        averageHRV: Double? = nil,
        habitAdherencePercent: Int? = nil,
        overdueTasksCount: Int? = nil,
        focusSessionCount: Int? = nil
    ) {
        self.totalFocusMinutes = totalFocusMinutes
        self.completedTasksCount = completedTasksCount
        self.averageEnergyScore = averageEnergyScore
        self.averageExecutiveFunctionScore = averageExecutiveFunctionScore
        self.peakProductivityWindow = peakProductivityWindow
        self.averageSleepHours = averageSleepHours
        self.averageSteps = averageSteps
        self.averageHRV = averageHRV
        self.habitAdherencePercent = habitAdherencePercent
        self.overdueTasksCount = overdueTasksCount
        self.focusSessionCount = focusSessionCount
    }
}

public struct PersonalAnalyticsReport: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var timeframe: InsightsTimeframe
    public var generatedAt: Date
    public var userId: String
    public var kpis: PersonalAnalyticsKPIs
    public var charts: [AnalyticsChartSeries]
    public var insights: [AnalyticsInsight]
    public var correlations: [AnalyticsInsight]
    public var coachRecommendations: [AnalyticsInsight]
    public var emptyStateMessages: [String]
    public var personalizationPromptContext: String
    public var hasSufficientData: Bool

    public init(
        id: String = UUID().uuidString,
        timeframe: InsightsTimeframe = .last7Days,
        generatedAt: Date = Date(),
        userId: String = "",
        kpis: PersonalAnalyticsKPIs = PersonalAnalyticsKPIs(),
        charts: [AnalyticsChartSeries] = [],
        insights: [AnalyticsInsight] = [],
        correlations: [AnalyticsInsight] = [],
        coachRecommendations: [AnalyticsInsight] = [],
        emptyStateMessages: [String] = [],
        personalizationPromptContext: String = "",
        hasSufficientData: Bool = false
    ) {
        self.id = id
        self.timeframe = timeframe
        self.generatedAt = generatedAt
        self.userId = userId
        self.kpis = kpis
        self.charts = charts
        self.insights = insights
        self.correlations = correlations
        self.coachRecommendations = coachRecommendations
        self.emptyStateMessages = emptyStateMessages
        self.personalizationPromptContext = personalizationPromptContext
        self.hasSufficientData = hasSufficientData
    }

    public static let empty = PersonalAnalyticsReport()
}
