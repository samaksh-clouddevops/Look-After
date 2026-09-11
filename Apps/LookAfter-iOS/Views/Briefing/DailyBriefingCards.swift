import SwiftUI
import LookAfterCore
import LookAfterFeatures
import LookAfterHealth

// MARK: - Health Snapshot

struct BriefingHealthSnapshotCard: View {
    let snapshot: BriefingHealthSnapshot

    private var collapsedDetail: String {
        [
            "\(snapshot.readinessScore)/100",
            snapshot.sleepHours.map { "Sleep \($0)" },
            "\(snapshot.energyPercent)% energy",
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    var body: some View {
        ElevatedSurface(padding: DesignSystem.spacingMD, emphasis: .subtle) {
            CalmHealthSnapshotLine(
                label: snapshot.readinessLabel,
                detail: collapsedDetail
            ) {
                VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
                    HStack(spacing: DesignSystem.spacingMD) {
                        snapshotMetric("Sleep", value: snapshot.sleepHours ?? "—")
                        snapshotMetric("Energy", value: "\(snapshot.energyPercent)%")
                        snapshotMetric("Recovery", value: snapshot.recoveryLabel)
                    }

                    HStack {
                        Text(UserFacingCopy.bestWindowTitle)
                            .font(.dsMetadata())
                            .foregroundColor(DesignSystem.textMuted)
                        Spacer()
                        Text(snapshot.focusWindow)
                            .font(.dsMetadata(weight: .semibold))
                            .foregroundColor(DesignSystem.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func snapshotMetric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.dsMetadata())
                .foregroundColor(DesignSystem.textMuted)
            Text(value)
                .font(.dsBody(weight: .semibold))
                .foregroundColor(DesignSystem.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Daily Summary

struct BriefingDailySummaryCard: View {
    let summary: BriefingDailySummary
    var compact: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 36
    @ScaledMetric(relativeTo: .title) private var compactScoreSize: CGFloat = 28

    var body: some View {
        BriefingCardContainer(title: summary.scoreLabel, icon: "chart.line.uptrend.xyaxis", compact: compact) {
            HStack(alignment: .top, spacing: DesignSystem.spacingMD) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(summary.score)")
                        .font(.system(size: compact ? compactScoreSize : scoreSize, weight: .bold, design: .default))
                        .foregroundColor(DesignSystem.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("/ \(summary.maxScore) · \(summary.scoreBand)")
                        .font(.dsMetadata())
                        .foregroundColor(DesignSystem.textMuted)
                }

                if !summary.narrative.isEmpty {
                    Text(summary.narrative)
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Sleep

struct BriefingSleepCard: View {
    let sleep: BriefingSleepData
    var compact: Bool
    var connectionStatus: HealthConnectionStatus?
    var onConnectHealth: () -> Void
    var onHealthPrimaryAction: () -> Void
    var onSeeHealthDetails: (() -> Void)?
    var onLearnMore: (() -> Void)?

    var body: some View {
        BriefingCardContainer(
            title: "Sleep",
            icon: "bed.double.fill",
            iconGradient: DesignSystem.accentGradient,
            compact: compact
        ) {
            if sleep.isAvailable {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignSystem.spacingSM) {
                    metric("Total", value: sleep.totalHours.map { String(format: "%.1fh", $0) } ?? "—")
                    metric("Deep", value: sleep.deepHours.map { String(format: "%.1fh", $0) } ?? "—")
                    metric("REM", value: sleep.remHours.map { String(format: "%.1fh", $0) } ?? "—")
                    metric("Quality", value: sleep.qualityPercent.map { "\($0)%" } ?? "—")
                }
                if sleep.sleepDebtHours > 0 {
                    Label(String(format: "Sleep debt: %.1fh", sleep.sleepDebtHours), systemImage: "moon.zzz.fill")
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .foregroundColor(DesignSystem.warning)
                }
            } else {
                healthStatusEmptyState(
                    status: connectionStatus,
                    onPrimaryAction: onHealthPrimaryAction,
                    onConnectFallback: onConnectHealth,
                    onSeeDetails: onSeeHealthDetails,
                    onLearnMore: onLearnMore
                )
            }
        }
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundColor(DesignSystem.textMuted)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .default))
                .foregroundColor(DesignSystem.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Mission

struct BriefingMissionCard: View {
    let mission: BriefingMissionData
    var compact: Bool
    var onAddTask: () -> Void
    var onReplanDay: (() -> Void)?

    var body: some View {
        BriefingCardContainer(title: UserFacingCopy.todayTitle, icon: "target", compact: compact) {
            if mission.tasks.isEmpty {
                VStack(spacing: 10) {
                    Text("Nothing on the list for today.")
                        .font(.system(size: 14, design: .default))
                        .foregroundColor(DesignSystem.textSecondary)
                    Button("Add something for today", action: onAddTask)
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundColor(DesignSystem.accentPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.spacingSM)
            } else {
                VStack(spacing: 8) {
                    ProgressView(value: Double(mission.completionPercent), total: 100)
                        .tint(DesignSystem.success)
                    Text("\(mission.completionPercent)% of today's list done")
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundColor(DesignSystem.textSecondary)

                    ForEach(mission.tasks.prefix(compact ? 3 : 8)) { task in
                        HStack(alignment: .top, spacing: DesignSystem.spacingSM) {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(task.isCompleted ? DesignSystem.success : DesignSystem.textMuted)
                                .layoutPriority(1)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.dsBody(weight: .semibold))
                                    .foregroundColor(task.isCompleted ? DesignSystem.textMuted : DesignSystem.textPrimary)
                                    .strikethrough(task.isCompleted)
                                    .dsPrimaryText(lineLimit: 2)
                                if let scheduleLabel = task.scheduleLabel {
                                    Text(scheduleLabel)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(DesignSystem.textMuted)
                                }
                            }
                            .layoutPriority(0)

                            Spacer(minLength: DesignSystem.spacingSM)

                            PriorityBadgeView(priority: task.priority)
                                .layoutPriority(1)
                        }
                    }

                    if mission.hiddenCompletedCount > 0 {
                        Text("+\(mission.hiddenCompletedCount) more completed")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.textSecondary)
                    }

                    if let onReplanDay {
                        Button(action: onReplanDay) {
                            Label("Adjust schedule", systemImage: "sparkles")
                                .font(.system(size: 13, weight: .semibold, design: .default))
                        }
                        .foregroundColor(DesignSystem.accentPrimary)
                        .padding(.top, DesignSystem.spacingXS)
                    }

                    Button(action: onAddTask) {
                        Label("All tasks", systemImage: "checklist")
                            .font(.system(size: 13, weight: .semibold, design: .default))
                    }
                    .foregroundColor(DesignSystem.textSecondary)
                }
            }
        }
    }
}

// MARK: - Calendar

struct BriefingCalendarCard: View {
    let calendar: BriefingCalendarData
    var compact: Bool
    var onConnectCalendar: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BriefingCardContainer(title: "Calendar", icon: "calendar", compact: compact) {
            if let title = calendar.nextEventTitle {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .default))
                        .foregroundColor(DesignSystem.textPrimary)
                    if let minutes = calendar.minutesUntilStart {
                        let countdown = minutes <= 0 ? "Starting now" : "In \(minutes) min"
                        Text(countdown)
                            .font(.system(size: 13, design: .default))
                            .foregroundColor(DesignSystem.accentPrimary)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(PremiumMotion.snappy(reduceMotion: reduceMotion), value: countdown)
                    }
                    if let duration = calendar.durationMinutes {
                        Text("\(duration) min")
                            .font(.system(size: 12, design: .default))
                            .foregroundColor(DesignSystem.textMuted)
                            .contentTransition(.numericText())
                            .animation(PremiumMotion.snappy(reduceMotion: reduceMotion), value: duration)
                    }
                }
            } else if calendar.isConnected {
                Text("Calendar's clear.")
                    .font(.system(size: 14, design: .default))
                    .foregroundColor(DesignSystem.textSecondary)
            } else {
                Button(action: onConnectCalendar) {
                    Label("Connect Calendar", systemImage: "calendar.badge.plus")
                        .font(.system(size: 13, weight: .semibold, design: .default))
                }
                .foregroundColor(DesignSystem.accentPrimary)
            }
        }
    }
}

// MARK: - Health

struct BriefingHealthCard: View {
    let health: BriefingHealthMetrics
    var compact: Bool
    var showsTitle: Bool = true
    var connectionStatus: HealthConnectionStatus?
    var onConnectHealth: () -> Void
    var onHealthPrimaryAction: () -> Void
    var onSeeHealthDetails: (() -> Void)?
    var onLearnMore: (() -> Void)?

    var body: some View {
        BriefingCardContainer(title: "Health", icon: "heart.fill", iconGradient: DesignSystem.healthGradient, compact: compact, showsHeader: showsTitle) {
            if health.isAvailable {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignSystem.spacingSM) {
                    miniMetric("Steps", value: formattedSteps, icon: "figure.walk")
                    miniMetric("Move", value: formattedMove, icon: "flame.fill")
                    miniMetric("Exercise", value: formattedExercise, icon: "figure.run")
                    miniMetric("Stand", value: formattedStand, icon: "figure.stand")
                    miniMetric("RHR", value: formattedRHR, icon: "heart.fill")
                    miniMetric("HRV", value: formattedHRV, icon: "waveform.path.ecg")
                }
            } else {
                healthStatusEmptyState(
                    status: connectionStatus,
                    onPrimaryAction: onHealthPrimaryAction,
                    onConnectFallback: onConnectHealth,
                    onSeeDetails: onSeeHealthDetails,
                    onLearnMore: onLearnMore
                )
            }
        }
    }

    private var formattedSteps: String {
        health.steps.map { "\($0)" } ?? "—"
    }

    private var formattedMove: String {
        health.moveRingPercent.map { "\($0)%" } ?? "—"
    }

    private var formattedExercise: String {
        health.exerciseMinutes.map { "\($0)m" } ?? "—"
    }

    private var formattedStand: String {
        health.standHours.map { "\($0)h" } ?? "—"
    }

    private var formattedRHR: String {
        health.restingHR.map { "\($0)" } ?? "—"
    }

    private var formattedHRV: String {
        health.hrv.map { "\($0)ms" } ?? "—"
    }

    private func miniMetric(_ label: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(DesignSystem.accentPrimary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .default))
                .foregroundColor(DesignSystem.textPrimary)
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .default))
                .foregroundColor(DesignSystem.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DesignSystem.contentSurfaceSubtle)
        )
    }
}

// MARK: - Cycle

struct BriefingCycleCard: View {
    let cycleData: BriefingCycleData
    var compact: Bool
    var onLog: () -> Void
    var onOpenDashboard: () -> Void

    var body: some View {
        BriefingCardContainer(title: "Cycle", icon: "circle.circle.fill", iconGradient: DesignSystem.healthGradient, compact: compact) {
            VStack(alignment: .leading, spacing: 10) {
                Text(cycleData.snapshot.phaseLabel)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignSystem.textPrimary)

                if let countdown = cycleData.snapshot.periodCountdownLabel {
                    Text(countdown)
                        .font(.system(size: 13))
                        .foregroundColor(DesignSystem.textSecondary)
                }

                if let insight = cycleData.topInsight {
                    Text(insight.headline)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DesignSystem.textPrimary)
                    Text(insight.body)
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.textMuted)
                        .lineLimit(compact ? 2 : 4)
                }

                HStack(spacing: 12) {
                    Button("Log how you feel", action: onLog)
                        .font(.system(size: 12, weight: .semibold))
                    Button("Open dashboard", action: onOpenDashboard)
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.textMuted)
                }
                .buttonStyle(.plain)

                Text(UserFacingCopy.medicalDisclaimer)
                    .font(.system(size: 10))
                    .foregroundColor(DesignSystem.textMuted)
            }
        }
    }
}

// MARK: - Habits

struct BriefingHabitsCard: View {
    let habits: [BriefingHabit]
    var compact: Bool
    var onToggle: (BriefingHabit) -> Void

    var body: some View {
        BriefingCardContainer(title: "Habits", icon: "checkmark.circle.fill", compact: compact) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignSystem.spacingSM) {
                ForEach(habits.prefix(compact ? 4 : habits.count)) { habit in
                    Button(action: {
                        onToggle(habit)
                    }, label: {
                        VStack(spacing: DesignSystem.spacingXS) {
                            HStack(spacing: DesignSystem.spacingXS) {
                                Image(systemName: habit.isCompletedToday ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(habit.isCompletedToday ? DesignSystem.success : DesignSystem.textMuted)

                                Image(systemName: habit.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(DesignSystem.accentPrimary)
                            }

                            Text(habit.title)
                                .font(.system(size: 12, weight: .semibold, design: .default))
                                .foregroundColor(DesignSystem.textPrimary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .padding(.horizontal, DesignSystem.spacingSM)
                        .padding(.vertical, DesignSystem.spacingSM)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(DesignSystem.contentSurfaceSubtle)
                        )
                    })
                    .buttonStyle(.plain)
                    .accessibilityLabel(habit.title)
                    .accessibilityValue(habit.isCompletedToday ? "Done today" : "Not done")
                }
            }
        }
    }
}

// MARK: - AI Coach

struct BriefingAICoachCard: View {
    let recommendation: String?
    var compact: Bool
    var onOpenCoach: () -> Void

    var body: some View {
        if let recommendation, !recommendation.isEmpty {
            BriefingCardContainer(title: UserFacingCopy.suggestedNextStepTitle, icon: "sparkles", compact: compact) {
                Text(UserFacingCopy.sanitize(recommendation))
                    .font(.system(size: compact ? 13 : 15, design: .default))
                    .foregroundColor(DesignSystem.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Ask follow-up", action: onOpenCoach)
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundColor(DesignSystem.accentPrimary)
            }
        }
    }
}

// MARK: - Focus Prediction

struct BriefingFocusPredictionCard: View {
    let windows: [BriefingFocusWindow]
    var compact: Bool

    var body: some View {
        BriefingCardContainer(title: UserFacingCopy.openWindowsTitle, icon: "clock", compact: compact) {
            ForEach(windows.prefix(compact ? 2 : windows.count)) { window in
                HStack(spacing: 10) {
                    Image(systemName: window.icon)
                        .foregroundColor(DesignSystem.accentPrimary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(window.label)
                            .font(.system(size: 13, weight: .semibold, design: .default))
                            .foregroundColor(DesignSystem.textPrimary)
                        Text(window.timeRange)
                            .font(.system(size: 11, design: .default))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                    Spacer()
                }
                .padding(.vertical, DesignSystem.spacingSM)
            }
        }
    }
}

// MARK: - Progress

struct BriefingProgressCard: View {
    let progress: BriefingProgressData
    var compact: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BriefingCardContainer(title: UserFacingCopy.progressTitle, icon: "chart.bar.fill", compact: compact) {
            // Counts on one row; duration + score on their own rows so wall clock
            // never reads as sitting under "Overdue" (LAY-C3).
            HStack(alignment: .top, spacing: DesignSystem.spacingSM) {
                stat("Completed", value: "\(progress.completedCount)")
                stat("Remaining", value: "\(progress.remainingCount)")
                stat("Overdue", value: "\(progress.overdueCount)", highlight: progress.overdueCount > 0 ? DesignSystem.error : nil)
            }
            HStack {
                Text(UserFacingCopy.taskTimeTitle)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundColor(DesignSystem.textMuted)
                Spacer()
                Text(progress.deepWorkMinutes.durationString)
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundColor(DesignSystem.textPrimary)
                    .contentTransition(.numericText())
                    .animation(PremiumMotion.snappy(reduceMotion: reduceMotion), value: progress.deepWorkMinutes)
            }
            .padding(.top, 4)
            HStack {
                Text(UserFacingCopy.dayScoreTitle)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundColor(DesignSystem.textMuted)
                Spacer()
                Text("\(progress.productivityScore)/100")
                    .font(.title3.weight(.bold))
                    .foregroundColor(DesignSystem.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                    .animation(PremiumMotion.snappy(reduceMotion: reduceMotion), value: progress.productivityScore)
            }
            .padding(.top, 2)
        }
    }

    private func stat(_ label: String, value: String, highlight: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundColor(DesignSystem.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .default))
                .foregroundColor(highlight ?? DesignSystem.textPrimary)
                .contentTransition(.numericText())
                .animation(PremiumMotion.snappy(reduceMotion: reduceMotion), value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Weekly Trends

struct BriefingWeeklyTrendsCard: View {
    let trends: BriefingWeeklyTrends
    var isLoading: Bool

    var body: some View {
        BriefingCardContainer(title: "Weekly Trends", icon: "waveform.path.ecg") {
            if isLoading {
                ProgressView().tint(DesignSystem.accentPrimary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                trendSection("Sleep (hours)", points: trends.sleep, color: DesignSystem.textSecondary, maxValue: 10)
                trendSection("Energy", points: trends.energy, color: DesignSystem.accentPrimary, maxValue: 100)
                trendSection("Steps", points: trends.steps, color: DesignSystem.textMuted, maxValue: 12_000)
                trendSection("Tasks", points: trends.taskCompletion, color: DesignSystem.textSecondary, maxValue: 100)
            }
        }
    }

    private func trendSection(_ title: String, points: [BriefingTrendPoint], color: Color, maxValue: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundColor(DesignSystem.textSecondary)
            BriefingMiniChart(points: points, color: color, maxValue: maxValue)
        }
    }
}

// MARK: - Alerts

struct BriefingAlertsCard: View {
    let alerts: [BriefingAlert]

    var body: some View {
        if !alerts.isEmpty {
            BriefingCardContainer(title: "Needs Attention", icon: "bell.badge.fill", iconGradient: DesignSystem.warmGradient) {
                ForEach(alerts) { alert in
                    HStack(alignment: .top, spacing: 10) {
                        Image.safeSystemName(alert.icon, fallback: "exclamationmark.circle")
                            .foregroundColor(color(for: alert.severity))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alert.title)
                                .font(.system(size: 13, weight: .semibold, design: .default))
                                .foregroundColor(DesignSystem.textPrimary)
                            Text(alert.message)
                                .font(.system(size: 12, design: .default))
                                .foregroundColor(DesignSystem.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func color(for severity: BriefingAlertSeverity) -> Color {
        switch severity {
        case .info: return DesignSystem.accentPrimary
        case .warning: return DesignSystem.warning
        case .urgent: return DesignSystem.error
        }
    }
}

// MARK: - Shared health status empty state

private func healthStatusEmptyState(
    status: HealthConnectionStatus?,
    onPrimaryAction: @escaping () -> Void,
    onConnectFallback: @escaping () -> Void,
    onSeeDetails: (() -> Void)? = nil,
    onLearnMore: (() -> Void)? = nil
) -> some View {
    let resolved = status ?? HealthConnectionStatusResolver.resolve(
        HealthConnectionStatusInput(
            isHealthEnabled: true,
            isHealthKitAvailable: true,
            isSignedIn: true
        )
    )
    return HealthStatusBanner(
        status: resolved,
        style: .compact,
        onPrimaryAction: {
            if resolved.primaryAction == .connect {
                onConnectFallback()
            } else {
                onPrimaryAction()
            }
        },
        onSeeDetails: onSeeDetails,
        onLearnMore: onLearnMore
    )
}

// MARK: - Section card (V5 — opaque content surface)

struct BriefingSectionCard<Content: View>: View {
    let title: String
    var subtitle: String?
    var icon: String?
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme

    init(title: String, subtitle: String? = nil, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            if !title.isEmpty {
                HStack(spacing: DesignSystem.spacingSM) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.dsIcon())
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                    VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                        Text(title)
                            .textStyleSectionLabel()
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .textStyleCaption()
                                .lineLimit(2)
                        }
                    }
                }
            } else if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .textStyleCaption()
                    .lineLimit(2)
            }

            content
        }
        .padding(DesignSystem.cardPaddingMin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sectionBackground)
        .overlay(sectionBorder)
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: LookAfterTypography.radiusCard, style: .continuous)
            .fill(DesignSystem.contentSurface)
            .shadow(
                color: DesignSystem.shadowElevated.opacity(DesignSystem.shadowOpacity(for: colorScheme)),
                radius: 18,
                x: 0,
                y: 8
            )
            .shadow(
                color: DesignSystem.shadowElevated.opacity(DesignSystem.shadowOpacity(for: colorScheme) * 0.45),
                radius: 4,
                x: 0,
                y: 2
            )
    }

    private var sectionBorder: some View {
        RoundedRectangle(cornerRadius: LookAfterTypography.radiusCard, style: .continuous)
            .stroke(DesignSystem.border, lineWidth: 1)
    }
}

// MARK: - Greeting header (reference layout)

struct BriefingGreetingHeader: View {
    let greeting: BriefingGreeting

    private var parts: (salutation: String, name: String) {
        BriefingGreetingParts.parse(greeting)
    }

    var body: some View {
        // Wave C: serif reserved for the user name only — keep until the type rule ships.
        VStack(alignment: .leading, spacing: 4) {
            if !parts.salutation.isEmpty {
                Text(parts.salutation)
                    .textStyleBriefingSalutation()
            }
            if !parts.name.isEmpty {
                Text(parts.name)
                    .textStyleBriefingUserName()
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            Text("Here's how today looks.")
                .textStyleCaption(color: DesignSystem.textSecondary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum BriefingGreetingParts {
    static func parse(_ greeting: BriefingGreeting) -> (salutation: String, name: String) {
        if !greeting.userName.isEmpty {
            let salutation = greeting.timeGreeting
                .trimmingCharacters(in: CharacterSet(charactersIn: ", "))
            if salutation.localizedCaseInsensitiveContains(greeting.userName) {
                let stripped = stripName(greeting.userName, from: salutation)
                return (stripped, greeting.userName)
            }
            return (salutation, greeting.userName)
        }

        let full = greeting.timeGreeting.trimmingCharacters(in: CharacterSet(charactersIn: ".!,"))
        if let comma = full.firstIndex(of: ",") {
            let salutation = String(full[..<comma]).trimmingCharacters(in: .whitespaces) + ","
            let name = String(full[full.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
            return (salutation, name)
        }
        return (full, "")
    }

    private static func stripName(_ name: String, from text: String) -> String {
        guard let range = text.range(of: name, options: .caseInsensitive) else { return text }
        var result = String(text[..<range.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        if !result.isEmpty, !result.hasSuffix(",") { result += "," }
        return result
    }
}

struct BriefingNextActionStrip: View {
    let hero: BriefingExecutiveHero
    let task: LifeTask?
    var onStart: () -> Void

    var body: some View {
        ElevatedSurface(padding: DesignSystem.spacingMD, emphasis: .subtle) {
            HStack(spacing: DesignSystem.spacingMD) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Do next")
                        .font(.dsMetadata(weight: .semibold))
                        .foregroundColor(DesignSystem.textMuted)
                    Text(hero.actionLine)
                        .font(.dsBody(weight: .semibold))
                        .foregroundColor(DesignSystem.textPrimary)
                        .lineLimit(2)
                    if let duration = hero.durationLabel {
                        Text(duration)
                            .font(.dsMetadata())
                            .foregroundColor(DesignSystem.textMuted)
                    }
                }

                Spacer(minLength: 8)

                Button(action: onStart) {
                    Text(hero.buttonLabel)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(DesignSystem.backgroundPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(DesignSystem.accentPrimary))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Snapshot strip (reference horizontal tiles)

struct BriefingSnapshotStrip: View {
    let snapshot: BriefingHealthSnapshot
    var healthNeedsAttention: Bool = false

    private let columns = [
        GridItem(.flexible(), spacing: DesignSystem.spacingSM),
        GridItem(.flexible(), spacing: DesignSystem.spacingSM),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: DesignSystem.spacingSM) {
            snapshotMetric(
                icon: "moon.fill",
                title: "Sleep",
                value: snapshot.sleepHours ?? "—",
                band: snapshot.sleepQuality ?? "—",
                bandIsPositive: isPositiveBand(snapshot.sleepQuality)
            )
            snapshotMetric(
                icon: "bolt.fill",
                title: "Energy",
                value: "\(snapshot.energyPercent)%",
                band: snapshot.hasOvernightHealthSignal
                    ? energyBand
                    : estimatedBand("Estimated · \(energyBand)"),
                bandIsPositive: snapshot.energyPercent >= 60
            )
            snapshotMetric(
                icon: "scope",
                title: "Recovery",
                value: snapshot.recoveryLabel,
                band: snapshot.hasOvernightHealthSignal
                    ? "\(snapshot.recoveryPercent)%"
                    : estimatedBand("Estimated · \(snapshot.recoveryPercent)%"),
                bandIsPositive: false
            )
            snapshotMetric(
                icon: "sun.max.fill",
                title: "Best window",
                value: focusWindowPrimary,
                band: focusWindowSecondary,
                bandIsPositive: false
            )
        }
    }

    private var energyBand: String {
        switch snapshot.energyPercent {
        case 75...: return "Feeling good"
        case 50..<75: return "Okay"
        default: return "Running low"
        }
    }

    private var focusWindowPrimary: String {
        let parts = snapshot.focusWindow.components(separatedBy: " – ")
        return parts.first ?? snapshot.focusWindow
    }

    private var focusWindowSecondary: String {
        let parts = snapshot.focusWindow.components(separatedBy: " – ")
        guard parts.count > 1 else { return "" }
        return parts[1]
    }

    private func estimatedBand(_ fallback: String) -> String {
        guard healthNeedsAttention else { return fallback }
        return "Connect Health for estimate"
    }

    private func isPositiveBand(_ band: String?) -> Bool {
        guard let band else { return false }
        return band.lowercased() == "good" || band.lowercased() == "high"
    }

    private func snapshotMetric(
        icon: String,
        title: String,
        value: String,
        band: String,
        bandIsPositive: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.spacingSM) {
            Image(systemName: icon)
                .font(.dsIcon())
                .foregroundColor(DesignSystem.accentPrimary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.dsTabLabel())
                    .foregroundColor(DesignSystem.textMuted)
                    .lineLimit(1)

                Text(value)
                    .font(.dsCaption(weight: .bold))
                    .foregroundColor(DesignSystem.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)

                if !band.isEmpty {
                    Text(band)
                        .font(.dsTabLabel())
                        .foregroundColor(bandIsPositive ? DesignSystem.accentPrimary : DesignSystem.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignSystem.spacingMD)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                .fill(DesignSystem.contentSurfaceSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                .stroke(DesignSystem.border.opacity(0.6), lineWidth: 1)
        )
        .clipped()
    }
}

// MARK: - Scroll affordance (footer of first viewport)

struct BriefingScrollAffordance: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            scrollChevron
            Text("Scroll to continue")
                .font(.dsMetadata())
                .foregroundColor(DesignSystem.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scroll to continue")
    }

    @ViewBuilder
    private var scrollChevron: some View {
        Image(systemName: "chevron.compact.down")
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(DesignSystem.accentPrimary.opacity(0.75))
            .symbolEffect(
                .bounce,
                options: .repeating.speed(0.35),
                isActive: !reduceMotion
            )
            .symbolEffectsRemoved(reduceMotion)
    }
}

// MARK: - Scroll chapter

struct BriefingChapterSection<Content: View>: View {
    let title: String
    let subtitle: String?
    var icon: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        BriefingSectionCard(title: title, subtitle: subtitle, icon: icon) {
            content()
        }
        .padding(.horizontal, DesignSystem.BriefingViewport.sectionHorizontal)
        .padding(.top, DesignSystem.spacingXS)
    }
}
