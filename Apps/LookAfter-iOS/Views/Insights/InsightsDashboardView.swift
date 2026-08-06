import SwiftUI
import LookAfterCore
import LookAfterAI
import LookAfterData
import LookAfterFeatures

/// Personalized health & productivity analytics — all metrics from real user data.
public struct InsightsDashboardView: View {

    @StateObject private var viewModel: InsightsViewModel
    @ObservedObject var brain: ExecutiveBrain

    public init(brain: ExecutiveBrain, userId: String = "") {
        self.brain = brain
        _viewModel = StateObject(wrappedValue: InsightsViewModel(userId: userId))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                PremiumBackground()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection

                        if viewModel.isLoading {
                            ProgressView("Analyzing your data…")
                                .tint(DesignSystem.accentPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                        } else {
                            if !viewModel.report.hasSufficientData {
                                emptyStateBanner
                            }

                            kpiSection
                            chartsSection
                            peakFocusSection
                            insightsSection(
                                title: "Your Patterns",
                                insights: viewModel.report.insights
                            )
                            insightsSection(
                                title: "Cross-Domain Correlations",
                                insights: viewModel.report.correlations.filter { !Self.isCycleCorrelation($0.message) }
                            )
                            if CycleFeatureGate.isEligible {
                                cyclePatternsSection
                            }
                            insightsSection(
                                title: "Suggestions",
                                insights: viewModel.report.coachRecommendations
                            )
                            personalizationSection
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Insights")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        Task { await viewModel.invalidateCache() }
                    }, label: {
                        Image(systemName: "arrow.clockwise")
                    })
                    .accessibilityLabel("Refresh insights")
                }
            }
            .task {
                await viewModel.loadInsights(for: viewModel.selectedTimeframe)
                syncPersonalizationContext()
            }
            .onChange(of: viewModel.summary.personalizationPromptContext) { _, _ in
                syncPersonalizationContext()
            }
            .onChange(of: viewModel.isPersonalizationEnabled) { _, _ in
                syncPersonalizationContext()
            }
        }
        .accessibilityIdentifier("screen-insights")
    }

    private var cacheStatusBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.isRefreshingInBackground ? "arrow.triangle.2.circlepath" : "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .semibold))
            if viewModel.isRefreshingInBackground {
                Text("Updating analytics in the background…")
            } else if let lastRefresh = viewModel.lastRefreshAt {
                Text("Showing cached data from \(lastRefresh.formatted(date: .abbreviated, time: .shortened))")
            } else {
                Text("Showing last synced analytics")
            }
        }
        .font(.system(size: 11, design: .default))
        .foregroundColor(DesignSystem.textMuted)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal Analytics")
                .font(.system(size: 24, weight: .bold, design: .default))
                .foregroundColor(DesignSystem.textPrimary)

            Text("All metrics from your HealthKit and \(UserFacingCopy.productName) history.")
                .font(.system(size: 13, design: .default))
                .foregroundColor(DesignSystem.textSecondary)

            if viewModel.isShowingCachedData || viewModel.isRefreshingInBackground {
                cacheStatusBanner
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(InsightsTimeframe.allCases) { timeframe in
                        Button(action: {
                            viewModel.selectedTimeframe = timeframe
                        }, label: {
                            Text(timeframe.rawValue)
                                .font(.system(size: 12, weight: .semibold, design: .default))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(
                                        viewModel.selectedTimeframe == timeframe
                                            ? DesignSystem.accentPrimary.opacity(0.35)
                                            : Color.white.opacity(0.06)
                                    )
                                )
                                .foregroundColor(
                                    viewModel.selectedTimeframe == timeframe
                                        ? DesignSystem.textPrimary
                                        : DesignSystem.textMuted
                                )
                        })
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var emptyStateBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Building your analytics", systemImage: "chart.line.uptrend.xyaxis")
                .font(.system(size: 15, weight: .bold, design: .default))
                .foregroundColor(DesignSystem.warning)

            ForEach(viewModel.report.emptyStateMessages, id: \.self) { message in
                Text("• \(message)")
                    .font(.system(size: 13, design: .default))
                    .foregroundColor(DesignSystem.textSecondary)
            }
        }
        .elevatedSurface()
        .padding(.horizontal)
    }

    private var kpiSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            if let minutes = viewModel.report.kpis.totalFocusMinutes {
                kpiCard(
                    title: "Timer time",
                    value: "\(minutes / 60)h \(minutes % 60)m",
                    icon: "clock.fill"
                )
            }
            if let count = viewModel.report.kpis.completedTasksCount {
                kpiCard(
                    title: "Tasks Completed",
                    value: "\(count)",
                    icon: "checkmark.circle.fill"
                )
            }
            if let energy = viewModel.report.kpis.averageEnergyScore {
                kpiCard(
                    title: "Avg Energy",
                    value: "\(Int(energy * 100))%",
                    icon: "bolt.fill",
                    isHighlighted: true
                )
            }
            if let ef = viewModel.report.kpis.averageExecutiveFunctionScore {
                kpiCard(
                    title: "Day capacity",
                    value: "\(ef)/100",
                    icon: "bolt.fill"
                )
            }
            if let sleep = viewModel.report.kpis.averageSleepHours {
                kpiCard(
                    title: "Avg Sleep",
                    value: String(format: "%.1fh", sleep),
                    icon: "bed.double.fill"
                )
            }
            if let steps = viewModel.report.kpis.averageSteps {
                kpiCard(
                    title: "Avg Steps",
                    value: steps.formatted(),
                    icon: "figure.walk"
                )
            }
        }
        .padding(.horizontal)
    }

    private var chartsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Trends")
                .font(.system(size: 18, weight: .bold, design: .default))
                .foregroundColor(DesignSystem.textPrimary)
                .padding(.horizontal)

            ForEach(viewModel.report.charts.filter(\.hasData)) { series in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(series.metric.title)
                            .font(.system(size: 15, weight: .semibold, design: .default))
                            .foregroundColor(DesignSystem.textPrimary)
                        Spacer()
                        if !series.unit.isEmpty {
                            Text(series.unit)
                                .font(.system(size: 11, design: .default))
                                .foregroundColor(DesignSystem.textMuted)
                        }
                    }

                    AnalyticsTrendChart(series: series)
                }
                .elevatedSurface()
                .padding(.horizontal)
            }

            if viewModel.report.charts.filter(\.hasData).isEmpty {
                Text("Not enough history for charts in this period.")
                    .font(.system(size: 13, design: .default))
                    .foregroundColor(DesignSystem.textMuted)
                    .padding(.horizontal)
            }
        }
    }

    @ViewBuilder
    private var cyclePatternsSection: some View {
        let insights = cyclePatternInsights
        insightsSection(title: "Cycle Patterns", insights: insights)
    }

    private var cyclePatternInsights: [AnalyticsInsight] {
        guard CycleFeatureGate.isEligible else { return [] }
        var results = viewModel.report.correlations.filter { Self.isCycleCorrelation($0.message) }
        let snapshot = CycleEngine.snapshot(CycleEngine.Input())
        if snapshot.isEnabled, !snapshot.phaseLabel.isEmpty {
            results.insert(
                AnalyticsInsight(
                    category: .correlation,
                    message: "Current phase: \(snapshot.phaseLabel)."
                ),
                at: 0
            )
        }
        let deterministic = CycleInsightBuilder.build(snapshot: snapshot, logs: CycleLogStore.load())
        for insight in deterministic.prefix(3) {
            results.append(
                AnalyticsInsight(
                    category: .correlation,
                    message: "\(insight.headline) — \(insight.body)"
                )
            )
        }
        return results
    }

    private static func isCycleCorrelation(_ message: String) -> Bool {
        let lower = message.lowercased()
        let keywords = ["phase", "luteal", "follicular", "menstrual", "ovulation", "period", "cycle"]
        return keywords.contains { lower.contains($0) }
    }

    @ViewBuilder
    private var peakFocusSection: some View {
        if let peak = viewModel.report.kpis.peakProductivityWindow, !peak.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(DesignSystem.accentPrimary)
                    Text(UserFacingCopy.bestWindowTitle)
                        .font(.system(size: 11, weight: .bold, design: .default))
                        .foregroundColor(DesignSystem.textMuted)
                }

                Text(peak)
                    .font(.system(size: 20, weight: .bold, design: .default))
                    .foregroundColor(DesignSystem.textPrimary)

                Text("Based on when you actually complete tasks during \(viewModel.selectedTimeframe.rawValue.lowercased()).")
                    .font(.system(size: 13, design: .default))
                    .foregroundColor(DesignSystem.textSecondary)
            }
            .elevatedSurface()
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func insightsSection(title: String, insights: [AnalyticsInsight]) -> some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .default))
                    .foregroundColor(DesignSystem.textPrimary)

                ForEach(insights) { insight in
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(color(for: insight.category))
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)
                        Text(UserFacingCopy.sanitize(insight.message))
                            .font(.system(size: 14, design: .default))
                            .foregroundColor(DesignSystem.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .elevatedSurface()
            .padding(.horizontal)
        }
    }

    private var personalizationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $viewModel.isPersonalizationEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Personalization")
                        .font(.system(size: 17, weight: .bold, design: .default))
                        .foregroundColor(DesignSystem.textPrimary)
                    Text("Feeds real analytics to the AI planner for personalized coaching.")
                        .font(.system(size: 12, design: .default))
                        .foregroundColor(DesignSystem.textMuted)
                }
            }
            .tint(DesignSystem.accentPrimary)

            if viewModel.isPersonalizationEnabled, !viewModel.summary.personalizationPromptContext.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Active Context:")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(DesignSystem.accentPrimary)

                    Text(viewModel.summary.personalizationPromptContext)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(DesignSystem.textSecondary)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.3)))
                }
            }
        }
        .elevatedSurface()
        .padding(.horizontal)
        .padding(.bottom, 24)
    }

    // MARK: - Helpers

    private func kpiCard(title: String, value: String, icon: String, isHighlighted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(isHighlighted ? DesignSystem.accentPrimary : DesignSystem.textMuted)
                Spacer()
            }

            Text(value)
                .font(.dsTitle())
                .foregroundColor(DesignSystem.textPrimary)

            Text(title)
                .font(.dsCaption())
                .foregroundColor(DesignSystem.textMuted)
        }
        .elevatedSurface()
    }

    private func color(for category: AnalyticsInsightCategory) -> Color {
        switch category {
        case .coach: return DesignSystem.accentPrimary
        default: return DesignSystem.textMuted
        }
    }

    private func syncPersonalizationContext() {
        if viewModel.isPersonalizationEnabled {
            let analytics: String?
            if let cached = viewModel.cachedAIContextPrompt, !cached.isEmpty {
                analytics = cached
            } else {
                analytics = viewModel.summary.personalizationPromptContext
            }
            brain.personalizationContext = UserCalibrationStore.combinedPersonalizationBlock(analyticsBlock: analytics)
        } else {
            brain.personalizationContext = nil
        }
    }
}

/// Reusable trend chart for Insights (mirrors Daily Briefing mini charts).
struct AnalyticsTrendChart: View {
    let series: AnalyticsChartSeries

    private var chartColor: Color {
        switch series.metric {
        case .productivityScore, .energy: return DesignSystem.accentPrimary
        default: return DesignSystem.textSecondary
        }
    }

    var body: some View {
        BriefingMiniChart(points: series.points.map {
            BriefingTrendPoint(id: $0.id, label: $0.label, value: $0.value)
        }, color: chartColor)
    }
}
