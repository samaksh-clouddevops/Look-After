import Foundation

/// Aggregated data insights summary for a specific timeframe.
/// Populated from `PersonalAnalyticsReport` — never contains fabricated metrics.
public struct InsightsSummary: Identifiable, Codable, Sendable {
    public var id: String
    public var timeframe: InsightsTimeframe
    public var totalFocusMinutes: Int
    public var completedTasksCount: Int
    public var averageEnergyScore: Double
    public var averageExecutiveFunctionScore: Int
    public var peakProductivityWindow: String
    public var crossDomainInsights: [String]
    public var personalizationPromptContext: String
    public var generatedAt: Date
    public var userId: String
    public var hasSufficientData: Bool
    public var emptyStateMessages: [String]

    public init(
        id: String = UUID().uuidString,
        timeframe: InsightsTimeframe = .last7Days,
        totalFocusMinutes: Int = 0,
        completedTasksCount: Int = 0,
        averageEnergyScore: Double = 0,
        averageExecutiveFunctionScore: Int = 0,
        peakProductivityWindow: String = "",
        crossDomainInsights: [String] = [],
        personalizationPromptContext: String = "",
        generatedAt: Date = Date(),
        userId: String = "",
        hasSufficientData: Bool = false,
        emptyStateMessages: [String] = []
    ) {
        self.id = id
        self.timeframe = timeframe
        self.totalFocusMinutes = totalFocusMinutes
        self.completedTasksCount = completedTasksCount
        self.averageEnergyScore = averageEnergyScore
        self.averageExecutiveFunctionScore = averageExecutiveFunctionScore
        self.peakProductivityWindow = peakProductivityWindow
        self.crossDomainInsights = crossDomainInsights
        self.personalizationPromptContext = personalizationPromptContext
        self.generatedAt = generatedAt
        self.userId = userId
        self.hasSufficientData = hasSufficientData
        self.emptyStateMessages = emptyStateMessages
    }

    public init(from report: PersonalAnalyticsReport) {
        self.id = report.id
        self.timeframe = report.timeframe
        self.totalFocusMinutes = report.kpis.totalFocusMinutes ?? 0
        self.completedTasksCount = report.kpis.completedTasksCount ?? 0
        self.averageEnergyScore = report.kpis.averageEnergyScore ?? 0
        self.averageExecutiveFunctionScore = report.kpis.averageExecutiveFunctionScore ?? 0
        self.peakProductivityWindow = report.kpis.peakProductivityWindow ?? ""
        self.crossDomainInsights = (report.correlations + report.insights).map(\.message)
        self.personalizationPromptContext = report.personalizationPromptContext
        self.generatedAt = report.generatedAt
        self.userId = report.userId
        self.hasSufficientData = report.hasSufficientData
        self.emptyStateMessages = report.emptyStateMessages
    }
}
