import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Today — full timeline with collapsible Executive Assistant bottom sheet.
struct TodayView: View {
    private enum TimelineDaySelection: String, CaseIterable, Identifiable {
        case today = "Today"
        case tomorrow = "Tomorrow"

        var id: String { rawValue }
    }

    @ObservedObject var briefingVM: DailyBriefingViewModel
    @ObservedObject var planningVM: ExecutivePlanningViewModel
    @ObservedObject var speechManager: SpeechRecognitionManager
    @ObservedObject var speechSynthesizer: PlanningSpeechSynthesizer
    @ObservedObject var modulesVM: LifeModulesViewModel
    @ObservedObject var tasksVM: TasksViewModel

    let lifeTimelineEvents: [LifeTimelineEvent]
    let tomorrowLifeTimelineEvents: [LifeTimelineEvent]
    let weatherSnapshot: WeatherDisplayService.Snapshot

    var onSettings: () -> Void
    var onViewTimeline: () -> Void
    var onReplanDay: () -> Void
    var onPlanTomorrow: () -> Void
    var onRefresh: () async -> Void
    var onPlanningSubmit: (_ text: String, _ startedWithVoice: Bool) -> Void
    var onNegotiationSelect: (String) -> Void
    var onRedesignWithAI: (String) -> Void = { _ in }
    var onOpenSleepDetail: () -> Void = {}
    var onOpenHealthDetail: () -> Void = {}
    var onOpenMedication: () -> Void = {}
    var onCompleteTimelineTask: (String) -> Void = { _ in }
    var onRescheduleTimelineTask: (String) -> Void = { _ in }
    var isPlanningTomorrow: Bool = false

    @State private var selectedDay: TimelineDaySelection = .today
    @State private var selectedMetricKind: TodayMetricKind?

    var body: some View {
        ZStack(alignment: .bottom) {
            timelineSection

            ExecutiveAssistantSheet(
                planningVM: planningVM,
                speechManager: speechManager,
                speechSynthesizer: speechSynthesizer,
                onSubmit: onPlanningSubmit,
                onNegotiationSelect: onNegotiationSelect,
                onRedesignWithAI: onRedesignWithAI
            )
        }
        .onAppear {
            planningVM.bootstrapTimeline(from: lifeTimelineEvents)
            planningVM.bootstrapTomorrowTimeline(from: tomorrowLifeTimelineEvents)
        }
        .onChange(of: lifeTimelineEvents.map(\.id)) { _, _ in
            planningVM.refreshTimeline(from: lifeTimelineEvents)
        }
        .onChange(of: tomorrowLifeTimelineEvents.map(\.id)) { _, _ in
            planningVM.refreshTomorrowTimeline(from: tomorrowLifeTimelineEvents)
        }
        .sheet(item: $selectedMetricKind) { kind in
            TodayMetricDetailSheet(
                kind: kind,
                briefingVM: briefingVM,
                capacity: briefingVM.executiveCapacity,
                weatherSnapshot: weatherSnapshot
            )
        }
        .accessibilityIdentifier("screen-today")
    }

    private var metricsInput: TodayMetricsInput {
        TodayMetricsInput(
            executiveCapacity: briefingVM.executiveCapacity,
            sleep: briefingVM.sleep,
            healthSnapshot: briefingVM.healthSnapshot,
            calendar: briefingVM.calendar,
            weather: TodayWeatherMetricsInput(
                temperatureCelsius: weatherSnapshot.temperatureCelsius,
                conditionLabel: weatherSnapshot.conditionLabel,
                isAvailable: weatherSnapshot.isAvailable
            ),
            medications: Self.loadMedications(),
            focusWindows: briefingVM.focusWindows,
            cycleSnapshot: briefingVM.cycleData.snapshot,
            completedTodayCount: briefingVM.progress.completedCount,
            isWeekend: Calendar.current.isDateInWeekend(Date())
        )
    }

    private var compactMetrics: [TodayExecutiveMetric] {
        TodayExecutiveMetricsEngine.select(metricsInput)
    }

    private static func loadMedications() -> [Medication] {
        guard let data = UserDefaults.standard.data(forKey: "lifeos_medications_list"),
              let medications = try? JSONDecoder().decode([Medication].self, from: data) else {
            return []
        }
        return medications
    }

    private func handleMetricTap(_ kind: TodayMetricKind) {
        switch kind {
        case .sleep:
            onOpenSleepDetail()
        case .recovery:
            onOpenHealthDetail()
        case .medication:
            onOpenMedication()
        case .cycle:
            selectedMetricKind = kind
        case .capacity, .freeTime, .weather, .focusWindow, .momentum:
            selectedMetricKind = kind
        }
    }

    private var timelineSection: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
                    headerBar
                    TodayGreetingHeader(greeting: briefingVM.greeting)
                    TodayCompactMetricsStrip(
                        metrics: compactMetrics,
                        capacity: briefingVM.executiveCapacity,
                        onMetricTap: handleMetricTap
                    )
                    timelineDayPicker
                    multiDayBanner
                    activeTimelineSection

                    if selectedDay == .today {
                        TodayEndOfDayJournalCard(
                            modulesVM: modulesVM,
                            tasksVM: tasksVM,
                            speechManager: speechManager
                        )
                    } else {
                        tomorrowHeadsUpCard
                    }
                }
                .frame(maxWidth: .infinity, minHeight: geo.size.height + 1, alignment: .top)
                .padding(.horizontal, DesignSystem.screenHorizontal)
                .padding(.top, DesignSystem.spacingSM)
                .padding(.bottom, scrollBottomInset)
            }
            .refreshable {
                await onRefresh()
            }
        }
    }

    /// Clears the executive assistant sheet so the journal card is fully scrollable.
    private var scrollBottomInset: CGFloat {
        let assistantClearance = ExecutiveAssistantMetrics.collapsedBottomPadding + 24
        let journalExtra: CGFloat = selectedDay == .today ? 200 : 40
        return assistantClearance + journalExtra
    }

    private var timelineDayPicker: some View {
        Picker("Day", selection: $selectedDay) {
            ForEach(TimelineDaySelection.allCases) { day in
                Text(day.rawValue).tag(day)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var multiDayBanner: some View {
        if selectedDay == .today {
            if let banner = planningVM.activeMultiDayBanner {
                multiDayBannerView(title: banner.title, dayIndex: banner.dayIndex, dayCount: banner.dayCount, sliceTitle: banner.sliceTitle)
            } else if let banner = TasksViewModel.activeMultiDayBanner(from: tasksVM.tasks) {
                multiDayBannerView(title: banner.title, dayIndex: banner.dayIndex, dayCount: banner.dayCount, sliceTitle: banner.sliceTitle)
            }
        }
    }

    private func multiDayBannerView(title: String, dayIndex: Int, dayCount: Int, sliceTitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title) — day \(dayIndex) of \(dayCount)")
                .font(.dsCaption())
                .foregroundColor(DesignSystem.accentPrimary)
            Text("Today: \(sliceTitle)")
                .font(.system(size: 11))
                .foregroundColor(DesignSystem.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignSystem.spacingMD)
        .padding(.vertical, DesignSystem.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DesignSystem.accentPrimary.opacity(0.1))
        )
    }

    @ViewBuilder
    private var activeTimelineSection: some View {
        switch selectedDay {
        case .today:
            ExecutiveLiveTimelineView(
                rows: planningVM.timelineRows,
                thinkingStep: planningVM.visibleThinkingStep,
                isProcessing: planningVM.isProcessing,
                title: "Your Day",
                onViewAll: onViewTimeline,
                onCompleteTask: onCompleteTimelineTask,
                onRescheduleTask: onRescheduleTimelineTask
            )
        case .tomorrow:
            ExecutiveLiveTimelineView(
                rows: planningVM.tomorrowTimelineRows,
                thinkingStep: nil,
                isProcessing: false,
                title: tomorrowTimelineTitle,
                emptyMessage: "Tap Plan to let your brain slot tomorrow's flexible work around fixed commitments.",
                isPreview: true,
                showPlanButton: true,
                isPlanning: isPlanningTomorrow,
                onViewAll: onViewTimeline,
                onPlan: onPlanTomorrow
            )
        }
    }

    private var tomorrowTimelineTitle: String {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) else {
            return "Tomorrow"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return "Tomorrow · \(formatter.string(from: tomorrow))"
    }

    private var tomorrowHeadsUpCard: some View {
        ElevatedSurface(padding: DesignSystem.spacingMD, emphasis: .subtle) {
            VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
                Label("Heads up", systemImage: "sunrise")
                    .font(.dsMetadata(weight: .semibold))
                    .foregroundColor(DesignSystem.accentPrimary)
                Text("This is a preview — your brain uses your life model, fixed blocks, and flexible tasks to plan tomorrow. Tap Plan to refine times with AI.")
                    .font(.dsCaption())
                    .foregroundColor(DesignSystem.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .center) {
            Text(selectedDay == .today ? "Today" : "Tomorrow")
                .font(.system(size: 34, weight: .bold, design: .default))
                .foregroundColor(DesignSystem.textPrimary)

            Spacer()

            if selectedDay == .today {
                Button(action: onReplanDay) {
                Group {
                    if planningVM.isReplanning {
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(DesignSystem.accentPrimary)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                }
                .frame(width: 36, height: 36)
                .background(Circle().fill(DesignSystem.backgroundElevated))
            }
            .buttonStyle(.plain)
            .disabled(planningVM.isReplanning || planningVM.isProcessing)
            .accessibilityLabel("Replan my day")
            } else {
                Button(action: onPlanTomorrow) {
                    Group {
                        if isPlanningTomorrow {
                            ProgressView()
                                .scaleEffect(0.75)
                                .tint(DesignSystem.accentPrimary)
                        } else {
                            Label("Plan", systemImage: "sparkles")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(DesignSystem.accentPrimary)
                        }
                    }
                    .frame(height: 36)
                    .padding(.horizontal, DesignSystem.spacingSM)
                    .background(Capsule().fill(DesignSystem.backgroundElevated))
                }
                .buttonStyle(.plain)
                .disabled(isPlanningTomorrow)
                .accessibilityLabel("Plan tomorrow with AI")
            }

            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DesignSystem.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(DesignSystem.backgroundElevated))
            }
            .accessibilityLabel("Settings")
        }
    }
}

private struct TodayGreetingHeader: View {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Legacy timeline helpers

private struct TodayFocusInsightModel {
    let prefix: String
    let highlight: String
    let suffix: String
}

private struct TodayFocusInsightLine: View {
    let model: TodayFocusInsightModel?

    var body: some View {
        if let model {
            (
                Text(model.prefix)
                    .foregroundColor(DesignSystem.textSecondary)
                + Text(model.highlight)
                    .foregroundColor(DesignSystem.accentPrimary)
                    .fontWeight(.semibold)
                + Text(model.suffix)
                    .foregroundColor(DesignSystem.textSecondary)
            )
            .font(.dsBody())
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Hero card

private struct TodayRecommendedHeroCard: View {
    let content: CalmHeroContent
    let durationLabel: String?
    var onPrimaryAction: () -> Void

    var body: some View {
        ElevatedSurface(padding: DesignSystem.spacingLG, emphasis: .prominent) {
            HStack(alignment: .top, spacing: DesignSystem.spacingMD) {
                VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
                    Label("RECOMMENDED FOR NOW", systemImage: "star.fill")
                        .font(.dsMetadata(weight: .semibold))
                        .foregroundColor(DesignSystem.accentPrimary)
                        .labelStyle(.titleAndIcon)

                    Text(content.title)
                        .font(.system(size: 22, weight: .bold, design: .default))
                        .foregroundColor(DesignSystem.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if let supporting = content.supportingLine, !supporting.isEmpty {
                        Text(supporting)
                            .font(.dsCaption())
                            .foregroundColor(DesignSystem.textSecondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let durationLabel, !durationLabel.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 11, weight: .medium))
                            Text(durationLabel)
                                .font(.dsMetadata())
                        }
                        .foregroundColor(DesignSystem.accentPrimary)
                    }

                    PremiumPrimaryButton(
                        content.primaryActionTitle.isEmpty ? "Continue" : content.primaryActionTitle,
                        icon: "arrow.right",
                        action: onPrimaryAction
                    )

                    if content.disclosure?.hasContent == true {
                        TodayWhyAffordance(content: content)
                    }
                }

                Spacer(minLength: 0)

                TodayHeroIllustration()
                    .frame(width: 72)
            }
        }
    }
}

private struct TodayHeroIllustration: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(DesignSystem.accentPrimary.opacity(0.12))
                .frame(width: 56, height: 56)
                .blur(radius: 8)

            VStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(DesignSystem.accentGradient)
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DesignSystem.accentPrimary.opacity(0.85))
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DesignSystem.accentPrimary.opacity(0.7))
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DesignSystem.backgroundSecondary.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(DesignSystem.accentPrimary.opacity(0.15), lineWidth: 1)
                    )
            )
        }
        .accessibilityHidden(true)
    }
}

private struct TodayWhyAffordance: View {
    let content: CalmHeroContent
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: DesignSystem.spacingSM) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 14, weight: .medium))
                    Text(isExpanded ? "Hide details" : "Why this?")
                        .font(.dsMetadata())
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(DesignSystem.textMuted)
            }
            .buttonStyle(.plain)

            if isExpanded, let disclosure = content.disclosure {
                VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
                    if let narrative = disclosure.narrative, !narrative.isEmpty {
                        Text(narrative)
                            .font(.dsCaption())
                            .foregroundColor(DesignSystem.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(disclosure.whyLines, id: \.self) { line in
                        Text(line)
                            .font(.dsCaption())
                            .foregroundColor(DesignSystem.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: - Timeline

private struct TodayTimelineEntry: Identifiable {
    let id: String
    let timeLabel: String
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    let isNow: Bool
}

private struct TodayTimelineSection: View {
    let nowTitle: String
    let nowDuration: String?
    let upcoming: [TodayTimelineEntry]
    var onViewAll: () -> Void

    var body: some View {
        ElevatedSurface(padding: DesignSystem.spacingLG, emphasis: .subtle) {
            VStack(alignment: .leading, spacing: DesignSystem.spacingLG) {
                HStack {
                    Text("Today's timeline")
                        .font(.dsHeadline())
                        .foregroundColor(DesignSystem.textPrimary)
                    Spacer()
                    Button(action: onViewAll) {
                        HStack(spacing: 4) {
                            Text("View all")
                                .font(.dsMetadata())
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(DesignSystem.accentPrimary)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
                    nowRow

                    ForEach(upcoming) { entry in
                        upcomingRow(entry)
                    }
                }
            }
        }
    }

    private var nowRow: some View {
        HStack(alignment: .top, spacing: DesignSystem.spacingSM) {
            timelineRail(isActive: true, showsLineBelow: !upcoming.isEmpty)

            VStack(alignment: .leading, spacing: 4) {
                Text("NOW")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(DesignSystem.accentPrimary)
                    .tracking(0.8)

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nowTitle)
                            .font(.dsBody(weight: .semibold))
                            .foregroundColor(DesignSystem.textPrimary)
                            .lineLimit(2)
                        if let nowDuration, !nowDuration.isEmpty {
                            Text(nowDuration)
                                .font(.dsMetadata())
                                .foregroundColor(DesignSystem.textMuted)
                        }
                    }

                    Spacer(minLength: 8)

                    Text("Next up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DesignSystem.accentPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(DesignSystem.backgroundSecondary)
                        )
                }
            }
        }
    }

    private func upcomingRow(_ entry: TodayTimelineEntry) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.spacingSM) {
            timelineRail(isActive: false, showsLineBelow: false)

            VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
                Text(entry.timeLabel)
                    .font(.dsMetadata())
                    .foregroundColor(DesignSystem.textMuted)

                HStack(spacing: DesignSystem.spacingSM) {
                    Image(systemName: entry.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(entry.iconColor)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.dsBody(weight: .semibold))
                            .foregroundColor(DesignSystem.textPrimary)
                            .lineLimit(2)
                        if !entry.subtitle.isEmpty {
                            Text(entry.subtitle)
                                .font(.dsMetadata())
                                .foregroundColor(DesignSystem.textMuted)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DesignSystem.textMuted)
                }
                .padding(DesignSystem.spacingSM)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous)
                        .fill(DesignSystem.backgroundSecondary.opacity(0.85))
                )
            }
        }
    }

    @ViewBuilder
    private func timelineRail(isActive: Bool, showsLineBelow: Bool) -> some View {
        VStack(spacing: 0) {
            Circle()
                .fill(isActive ? DesignSystem.accentPrimary : DesignSystem.textMuted.opacity(0.45))
                .frame(width: 8, height: 8)
            if showsLineBelow {
                Rectangle()
                    .fill(DesignSystem.divider)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 12)
    }
}

// MARK: - Formatters

private enum TodayFormatters {
    static func sleepDuration(_ hours: Double) -> String {
        let wholeHours = Int(hours)
        let minutes = Int((hours - Double(wholeHours)) * 60)
        if minutes > 0 {
            return "\(wholeHours)h \(minutes)m"
        }
        return String(format: "%.1fh", hours)
    }
}
