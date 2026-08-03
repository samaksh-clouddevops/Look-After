import SwiftUI
import LookAfterCore
import LookAfterFeatures

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

    var body: some View {
        BriefingCardContainer(title: summary.scoreLabel, icon: "chart.line.uptrend.xyaxis", compact: compact) {
            HStack(alignment: .top, spacing: DesignSystem.spacingMD) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(summary.score)")
                        .font(.system(size: compact ? 28 : 36, weight: .bold, design: .default))
                        .foregroundColor(DesignSystem.textPrimary)
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
    var onConnectHealth: () -> Void

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
                emptyHealthPrompt(onConnect: onConnectHealth)
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
                    Text("No tasks yet today.")
                        .font(.system(size: 14, design: .default))
                        .foregroundColor(DesignSystem.textSecondary)
                    Button("Create today's first task", action: onAddTask)
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundColor(DesignSystem.accentPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.spacingSM)
            } else {
                VStack(spacing: 8) {
                    ProgressView(value: Double(mission.completionPercent), total: 100)
                        .tint(DesignSystem.success)
                    Text("\(mission.completionPercent)% complete")
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundColor(DesignSystem.textMuted)

                    ForEach(mission.tasks.prefix(compact ? 3 : 5)) { task in
                        HStack(alignment: .top, spacing: DesignSystem.spacingSM) {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(task.isCompleted ? DesignSystem.success : DesignSystem.textMuted)
                                .layoutPriority(1)

                            Text(task.title)
                                .font(.dsBody(weight: .semibold))
                                .foregroundColor(task.isCompleted ? DesignSystem.textMuted : DesignSystem.textPrimary)
                                .strikethrough(task.isCompleted)
                                .dsPrimaryText(lineLimit: 2)
                                .layoutPriority(0)

                            Spacer(minLength: DesignSystem.spacingSM)

                            PriorityBadgeView(priority: task.priority)
                                .layoutPriority(1)
                        }
                    }

                    if let onReplanDay {
                        Button(action: onReplanDay) {
                            Label("Replan My Day", systemImage: "sparkles")
                                .font(.system(size: 13, weight: .semibold, design: .default))
                        }
                        .foregroundColor(DesignSystem.accentPrimary)
                        .padding(.top, DesignSystem.spacingXS)
                    }
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

    var body: some View {
        BriefingCardContainer(title: "Calendar", icon: "calendar", compact: compact) {
            if let title = calendar.nextEventTitle {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .default))
                        .foregroundColor(DesignSystem.textPrimary)
                    if let minutes = calendar.minutesUntilStart {
                        Text(minutes <= 0 ? "Starting now" : "In \(minutes) min")
                            .font(.system(size: 13, design: .default))
                            .foregroundColor(DesignSystem.accentPrimary)
                    }
                    if let duration = calendar.durationMinutes {
                        Text("\(duration) min")
                            .font(.system(size: 12, design: .default))
                            .foregroundColor(DesignSystem.textMuted)
                    }
                }
            } else if calendar.isConnected {
                Text("Nothing scheduled.")
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
    var onConnectHealth: () -> Void

    var body: some View {
        BriefingCardContainer(title: "Health", icon: "heart.fill", iconGradient: DesignSystem.healthGradient, compact: compact) {
            if health.isAvailable {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: compact ? 3 : 3), spacing: DesignSystem.spacingSM) {
                    if let steps = health.steps { miniMetric("Steps", value: "\(steps)", icon: "figure.walk") }
                    if let move = health.moveRingPercent { miniMetric("Move", value: "\(move)%", icon: "flame.fill") }
                    if let exercise = health.exerciseMinutes { miniMetric("Exercise", value: "\(exercise)m", icon: "figure.run") }
                    if let stand = health.standHours { miniMetric("Stand", value: "\(stand)h", icon: "figure.stand") }
                    if let rhr = health.restingHR { miniMetric("RHR", value: "\(rhr)", icon: "heart.fill") }
                    if let hrv = health.hrv { miniMetric("HRV", value: "\(hrv)ms", icon: "waveform.path.ecg") }
                }
            } else {
                emptyHealthPrompt(onConnect: onConnectHealth)
            }
        }
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
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
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
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(habits.prefix(compact ? 4 : habits.count)) { habit in
                    Button {
                        onToggle(habit)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: habit.isCompletedToday ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(habit.isCompletedToday ? DesignSystem.success : DesignSystem.textMuted)
                            Image(systemName: habit.icon)
                                .font(.system(size: 11))
                                .foregroundColor(DesignSystem.accentPrimary)
                            Text(habit.title)
                                .font(.system(size: 12, weight: .semibold, design: .default))
                                .foregroundColor(DesignSystem.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
                    }
                    .buttonStyle(.plain)
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
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - Progress

struct BriefingProgressCard: View {
    let progress: BriefingProgressData
    var compact: Bool

    var body: some View {
        BriefingCardContainer(title: UserFacingCopy.progressTitle, icon: "chart.bar.fill", compact: compact) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignSystem.spacingSM) {
                stat("Completed", value: "\(progress.completedCount)")
                stat("Remaining", value: "\(progress.remainingCount)")
                stat("Overdue", value: "\(progress.overdueCount)", highlight: progress.overdueCount > 0 ? DesignSystem.error : nil)
                stat(UserFacingCopy.taskTimeTitle, value: "\(progress.deepWorkMinutes)m")
            }
            HStack {
                Text(UserFacingCopy.dayScoreTitle)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundColor(DesignSystem.textMuted)
                Spacer()
                Text("\(progress.productivityScore)")
                    .font(.system(size: 20, weight: .bold, design: .default))
                    .foregroundColor(DesignSystem.textMuted)
            }
            .padding(.top, 4)
        }
    }

    private func stat(_ label: String, value: String, highlight: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundColor(DesignSystem.textMuted)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .default))
                .foregroundColor(highlight ?? DesignSystem.textPrimary)
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
                        Image(systemName: alert.icon)
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

// MARK: - Shared empty state

private func emptyHealthPrompt(onConnect: @escaping () -> Void) -> some View {
    VStack(spacing: 10) {
        Text("Connect Apple Health to see sleep, energy, and activity.")
            .font(.system(size: 13, design: .default))
            .foregroundColor(DesignSystem.textSecondary)
            .multilineTextAlignment(.center)
        Button(action: onConnect) {
            Label("Connect Health", systemImage: "heart.text.square.fill")
                .font(.system(size: 13, weight: .semibold, design: .default))
        }
        .foregroundColor(DesignSystem.accentPrimary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, DesignSystem.spacingSM)
}

// MARK: - Greeting header (reference layout)

struct BriefingGreetingHeader: View {
    let greeting: BriefingGreeting

    private var parts: (salutation: String, name: String) {
        BriefingGreetingParts.parse(greeting)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !parts.salutation.isEmpty {
                Text(parts.salutation)
                    .font(.dsBody())
                    .foregroundColor(DesignSystem.textSecondary)
            }
            if !parts.name.isEmpty {
                Text(parts.name)
                    .font(.system(size: 36, weight: .bold, design: .default))
                    .foregroundColor(DesignSystem.textPrimary)
                    .lineLimit(1)
            }
            Text("Focus. Progress. Peace.")
                .font(.dsMetadata())
                .foregroundColor(DesignSystem.textMuted)
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

// MARK: - Day overview (replaces large hero)

struct BriefingDayOverviewCard: View {
    let briefing: MorningDayBriefing
    var isMorningStyle: Bool
    var onOpenTimeline: () -> Void
    var onOpenTasks: () -> Void
    var onCapture: () -> Void

    var body: some View {
        ElevatedSurface(padding: DesignSystem.spacingMD, emphasis: .standard) {
            VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
                HStack {
                    Label(
                        isMorningStyle ? "MORNING BRIEFING" : "TODAY",
                        systemImage: isMorningStyle ? "sun.horizon.fill" : "calendar"
                    )
                    .font(.dsMetadata(weight: .semibold))
                    .foregroundColor(DesignSystem.accentPrimary)
                    .labelStyle(.titleAndIcon)

                    Spacer()

                    Button("Timeline", action: onOpenTimeline)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.accentPrimary)
                }

                Text(briefing.introLine)
                    .font(.dsBody())
                    .foregroundColor(DesignSystem.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let sleepLine = briefing.sleepLine {
                    Label(sleepLine, systemImage: "bed.double.fill")
                        .font(.dsMetadata())
                        .foregroundColor(DesignSystem.textMuted)
                        .labelStyle(.titleAndIcon)
                }

                if let idealSleepLine = briefing.idealSleepLine {
                    Label(idealSleepLine, systemImage: "moon.zzz.fill")
                        .font(.dsMetadata())
                        .foregroundColor(DesignSystem.textMuted)
                        .labelStyle(.titleAndIcon)
                }

                overviewGrid

                if !briefing.planItems.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Plan")
                            .font(.dsMetadata(weight: .semibold))
                            .foregroundColor(DesignSystem.textMuted)

                        ForEach(briefing.planItems.prefix(5)) { item in
                            planRow(item)
                        }
                    }
                }

                if !briefing.pendingHighlights.isEmpty {
                    ForEach(briefing.pendingHighlights.prefix(2), id: \.self) { line in
                        Text(line)
                            .font(.dsCaption())
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                }

                HStack(spacing: DesignSystem.spacingSM) {
                    Button(action: onOpenTasks) {
                        Label("All tasks", systemImage: "checklist")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(DesignSystem.textSecondary)

                    Spacer()

                    Button(action: onCapture) {
                        Label("Capture", systemImage: "mic.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(DesignSystem.accentPrimary)
                }
            }
        }
    }

    private var overviewGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignSystem.spacingSM) {
            statChip(icon: "gauge.with.dots.needle.33percent", title: "Capacity", value: briefing.capacityLabel)
            statChip(icon: "checklist", title: "Work", value: workLeftLabel)
            if let free = briefing.freeTimeLabel {
                statChip(icon: "clock", title: "Open", value: free)
            }
            if let next = briefing.nextEventLabel {
                statChip(icon: "calendar", title: "Next", value: next)
            }
        }
    }

    private var workLeftLabel: String {
        var parts: [String] = []
        if briefing.completedCount > 0 {
            parts.append("\(briefing.completedCount) done")
        }
        parts.append("\(briefing.remainingCount) left")
        if briefing.overdueCount > 0 {
            parts.append("\(briefing.overdueCount) overdue")
        }
        return parts.joined(separator: " · ")
    }

    private func statChip(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DesignSystem.textMuted)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.dsCaption(weight: .semibold))
                .foregroundColor(DesignSystem.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                .fill(DesignSystem.backgroundElevated.opacity(0.55))
        )
    }

    private func planRow(_ item: MorningPlanItem) -> some View {
        HStack(spacing: 8) {
            Text(item.timeLabel ?? "—")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(item.isCompleted ? DesignSystem.textMuted : DesignSystem.accentPrimary)
                .frame(width: 52, alignment: .leading)

            Text(item.title)
                .font(.dsCaption())
                .foregroundColor(item.isCompleted ? DesignSystem.textMuted : DesignSystem.textPrimary)
                .lineLimit(1)
                .strikethrough(item.isCompleted)

            Spacer(minLength: 0)
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
            HStack {
                Text("TODAY'S SNAPSHOT")
                    .font(.dsMetadata(weight: .semibold))
                    .foregroundColor(DesignSystem.textMuted)
                    .tracking(0.6)
                Spacer()
                Text("View all")
                    .font(.dsMetadata())
                    .foregroundColor(DesignSystem.accentPrimary.opacity(0.85))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DesignSystem.accentPrimary.opacity(0.85))
            }

            GeometryReader { geo in
                let gap = DesignSystem.spacingXS
                let tileWidth = max(72, (geo.size.width - gap * 3) / 4)

                HStack(spacing: gap) {
                    snapshotTile(
                        width: tileWidth,
                        icon: "moon.fill",
                        title: "Sleep",
                        value: snapshot.sleepHours ?? "—",
                        band: snapshot.sleepQuality ?? "—",
                        bandIsPositive: isPositiveBand(snapshot.sleepQuality)
                    )
                    snapshotTile(
                        width: tileWidth,
                        icon: "bolt.fill",
                        title: "Energy",
                        value: "\(snapshot.energyPercent)%",
                        band: energyBand,
                        bandIsPositive: snapshot.energyPercent >= 60
                    )
                    snapshotTile(
                        width: tileWidth,
                        icon: "scope",
                        title: "Recovery",
                        value: snapshot.recoveryLabel,
                        band: "\(snapshot.recoveryPercent)%",
                        bandIsPositive: false
                    )
                    snapshotTile(
                        width: tileWidth,
                        icon: "sun.max.fill",
                        title: "Window",
                        value: focusWindowPrimary,
                        band: focusWindowSecondary,
                        bandIsPositive: false,
                        compactValue: true
                    )
                }
            }
            .frame(height: 96)
        }
    }

    private var energyBand: String {
        switch snapshot.energyPercent {
        case 75...: return "Good"
        case 50..<75: return "Fair"
        default: return "Low"
        }
    }

    private var focusWindowPrimary: String {
        let parts = snapshot.focusWindow.components(separatedBy: " – ")
        return parts.first ?? snapshot.focusWindow
    }

    private var focusWindowSecondary: String {
        let parts = snapshot.focusWindow.components(separatedBy: " – ")
        guard parts.count > 1 else { return "" }
        return "– \(parts[1])"
    }

    private func isPositiveBand(_ band: String?) -> Bool {
        guard let band else { return false }
        return band.lowercased() == "good" || band.lowercased() == "high"
    }

    private func snapshotTile(
        width: CGFloat,
        icon: String,
        title: String,
        value: String,
        band: String,
        bandIsPositive: Bool,
        compactValue: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DesignSystem.accentPrimary)

            Text(value)
                .font(.system(size: compactValue ? 13 : 16, weight: .bold, design: .default))
                .foregroundColor(DesignSystem.textPrimary)
                .lineLimit(compactValue ? 2 : 1)
                .minimumScaleFactor(0.65)
                .fixedSize(horizontal: false, vertical: true)

            if !band.isEmpty {
                Text(band)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(bandIsPositive ? DesignSystem.accentPrimary : DesignSystem.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Text(title)
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(DesignSystem.textMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusSurface, style: .continuous)
                .fill(DesignSystem.backgroundElevated.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.radiusSurface, style: .continuous)
                .stroke(DesignSystem.accentPrimary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Scroll affordance (footer of first viewport)

struct BriefingScrollAffordance: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "chevron.compact.down")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(DesignSystem.accentPrimary.opacity(0.5))
                .symbolEffect(.bounce, options: .repeating.speed(0.35))
            Text("Scroll to continue")
                .font(.dsMetadata())
                .foregroundColor(DesignSystem.textMuted.opacity(0.5))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scroll to continue")
    }
}

// MARK: - Scroll chapter

struct BriefingChapterSection<Content: View>: View {
    let title: String
    let subtitle: String?
    var icon: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
            HStack(spacing: DesignSystem.spacingSM) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DesignSystem.accentGradient)
                }
                Text(title)
                    .font(.dsHeadline())
                    .foregroundColor(DesignSystem.textPrimary)
                Spacer(minLength: 0)
            }

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.dsCaption())
                    .foregroundColor(DesignSystem.textSecondary)
                    .lineLimit(2)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, DesignSystem.screenHorizontal)
        .padding(.top, DesignSystem.spacingMD)
    }
}
