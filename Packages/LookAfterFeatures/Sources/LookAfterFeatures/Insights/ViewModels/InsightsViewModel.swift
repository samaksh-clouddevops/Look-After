import Foundation
import LookAfterCore
import LookAfterAI
import LookAfterData

/// ViewModel for personalized health & productivity analytics.
@MainActor
public final class InsightsViewModel: ObservableObject {

    @Published public var selectedTimeframe: InsightsTimeframe = .last7Days {
        didSet {
            Task { await loadInsights(for: selectedTimeframe) }
        }
    }

    @Published public var summary: InsightsSummary = InsightsSummary()
    @Published public var report: PersonalAnalyticsReport = .empty
    @Published public var isLoading: Bool = false
    @Published public var isRefreshingInBackground: Bool = false
    @Published public var isShowingCachedData: Bool = false
    @Published public var lastRefreshAt: Date?
    @Published public var isPersonalizationEnabled: Bool = true
    @Published public var errorMessage: String?

    private let analyticsEngine: PersonalAnalyticsEngine
    private let analyticsService: BackgroundAnalyticsService?
    private let userId: String

    public init(
        analyticsEngine: PersonalAnalyticsEngine? = nil,
        analyticsService: BackgroundAnalyticsService? = BackgroundAnalyticsService.shared,
        userId: String = ""
    ) {
        self.userId = userId
        self.analyticsService = analyticsService
        if let analyticsEngine {
            self.analyticsEngine = analyticsEngine
        } else {
            self.analyticsEngine = PersonalAnalyticsEngine(
                fetchBehaviorEvents: { await PersonalAnalyticsBehaviorLoader.fetchEvents() }
            )
        }
    }

    /// Reads precomputed cache first, then refreshes incrementally in the background.
    public func loadInsights(for timeframe: InsightsTimeframe) async {
        errorMessage = nil

        if let analyticsService {
            if let cached = analyticsService.cachedReport(timeframe: timeframe, userId: userId) {
                applyReport(cached)
                isLoading = false
                isShowingCachedData = true
                lastRefreshAt = analyticsService.lastRefreshAt
                    ?? AnalyticsCacheManager.shared.lastRefreshDate(userId: userId)
            } else {
                isLoading = true
                isShowingCachedData = false
            }

            isRefreshingInBackground = analyticsService.isRefreshing
            await analyticsService.refreshIfNeeded(userId: userId, trigger: .insightsOpened)

            if let refreshed = analyticsService.cachedReport(timeframe: timeframe, userId: userId) {
                applyReport(refreshed)
                isShowingCachedData = false
                lastRefreshAt = analyticsService.lastRefreshAt
            } else if report == .empty {
                let built = await analyticsEngine.buildReport(timeframe: timeframe, userId: userId)
                applyReport(built)
                isShowingCachedData = false
            }

            isRefreshingInBackground = false
            isLoading = false
            return
        }

        isLoading = true
        let built = await analyticsEngine.buildReport(timeframe: timeframe, userId: userId)
        applyReport(built)
        isLoading = false
    }

    public func invalidateCache() async {
        if let analyticsService {
            analyticsService.invalidate(userId: userId)
            await analyticsService.refreshIfNeeded(userId: userId, trigger: .manual, force: true)
            await loadInsights(for: selectedTimeframe)
            return
        }

        analyticsEngine.invalidateCache()
        await loadInsights(for: selectedTimeframe)
    }

    /// Compact cached AI summary for coach personalization (avoids rebuilding from raw data).
    public var cachedAIContextPrompt: String? {
        analyticsService?.cachedAIContext(userId: userId)?.promptBlock
    }

    private func applyReport(_ built: PersonalAnalyticsReport) {
        report = built
        summary = InsightsSummary(from: built)
    }
}
