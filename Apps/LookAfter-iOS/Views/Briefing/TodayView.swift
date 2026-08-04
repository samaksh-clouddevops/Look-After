import SwiftUI
import Combine
import LookAfterCore
import LookAfterFeatures

/// Today — full timeline with collapsible Executive Assistant bottom sheet.
struct TodayView: View {
    private enum TimelineDaySelection: String, CaseIterable, Identifiable {
        case today = "Today"
        case tomorrow = "Tomorrow"

        var id: String { rawValue }
    }

    let briefingVM: DailyBriefingViewModel
    let planningVM: ExecutivePlanningViewModel
    let speechManager: SpeechRecognitionManager
    let speechSynthesizer: PlanningSpeechSynthesizer
    let modulesVM: LifeModulesViewModel
    let tasksVM: TasksViewModel

    let lifeTimelineEvents: [LifeTimelineEvent]
    let tomorrowLifeTimelineEvents: [LifeTimelineEvent]
    let weatherSnapshot: WeatherDisplayService.Snapshot

    var onSettings: () -> Void
    var onOpenTasks: () -> Void = {}
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
    var onStartTask: (LifeTask) -> Void = { _ in }
    var onEditTask: (LifeTask) -> Void = { _ in }
    var isPlanningTomorrow: Bool = false

    @State private var selectedDay: TimelineDaySelection = .today
    @State private var selectedMetricKind: TodayMetricKind?
    @State private var selectedCalendarDate = Calendar.current.startOfDay(for: Date())
    @State private var expandedPriorityId: String?

    var body: some View {
        timelineSection
            .overlay(alignment: .bottom) {
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
        .onChange(of: lifeTimelineSignature) { _, _ in
            planningVM.refreshTimeline(from: lifeTimelineEvents)
        }
        .onChange(of: tomorrowLifeTimelineSignature) { _, _ in
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

    private var lifeTimelineSignature: String {
        "\(lifeTimelineEvents.count)|\(lifeTimelineEvents.first?.id ?? "")|\(lifeTimelineEvents.last?.id ?? "")"
    }

    private var tomorrowLifeTimelineSignature: String {
        "\(tomorrowLifeTimelineEvents.count)|\(tomorrowLifeTimelineEvents.first?.id ?? "")|\(tomorrowLifeTimelineEvents.last?.id ?? "")"
    }

    private var timelineSection: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: DesignSystem.spacingLG, pinnedViews: []) {
                    todayHeader
                    LAWeekDateStrip(
                        days: weekDays,
                        selectedDate: $selectedCalendarDate
                    )
                    .onChange(of: selectedCalendarDate) { _, newDate in
                        syncSelectedDay(from: newDate)
                    }

                    if isSelectedToday {
                        TodayMultiDayBanner(planningVM: planningVM, tasksVM: tasksVM)
                        TodayPrioritiesSection(
                            tasksVM: tasksVM,
                            expandedPriorityId: $expandedPriorityId,
                            onOpenTasks: onOpenTasks,
                            onStartTask: onStartTask,
                            onEditTask: onEditTask,
                            onCompleteTimelineTask: onCompleteTimelineTask
                        )
                        TodayScheduleSection(
                            planningVM: planningVM,
                            isTomorrow: false,
                            isPlanningTomorrow: isPlanningTomorrow,
                            tasksVM: tasksVM,
                            onViewTimeline: onViewTimeline,
                            onPlanTomorrow: onPlanTomorrow,
                            onCompleteTimelineTask: onCompleteTimelineTask,
                            onRescheduleTimelineTask: onRescheduleTimelineTask,
                            onStartTask: onStartTask,
                            onEditTask: onEditTask
                        )
                        TodayEndOfDayJournalCard(
                            modulesVM: modulesVM,
                            tasksVM: tasksVM,
                            speechManager: speechManager
                        )
                        viewFullTimelineLink
                    } else if isSelectedTomorrow {
                        tomorrowHeadsUpCard
                        TodayScheduleSection(
                            planningVM: planningVM,
                            isTomorrow: true,
                            isPlanningTomorrow: isPlanningTomorrow,
                            tasksVM: tasksVM,
                            onViewTimeline: onViewTimeline,
                            onPlanTomorrow: onPlanTomorrow,
                            onCompleteTimelineTask: onCompleteTimelineTask,
                            onRescheduleTimelineTask: onRescheduleTimelineTask,
                            onStartTask: onStartTask,
                            onEditTask: onEditTask
                        )
                    } else {
                        Text("No plan for this day yet.")
                            .textStyleCaption()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, DesignSystem.BriefingViewport.sectionHorizontal)
                .safeAreaPadding(.top, DesignSystem.spacingSM)
                .padding(.bottom, scrollBottomInset)
            }
            .refreshable {
                await onRefresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: .tourScrollToAnchor)) { note in
                guard let raw = note.userInfo?[TourScrollUserInfoKey.anchorID] as? String else { return }
                if raw == AppFeatureTourAnchorID.todayTimeline.rawValue {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(AppFeatureTourAnchorID.todayTimeline.rawValue, anchor: .center)
                    }
                } else if raw == AppFeatureTourAnchorID.todayAssistant.rawValue {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(AppFeatureTourAnchorID.todayTimeline.rawValue, anchor: .top)
                    }
                }
            }
        }
    }

    private var todayHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            TodayHeaderBar(
                planningVM: planningVM,
                isSelectedToday: isSelectedToday,
                isSelectedTomorrow: isSelectedTomorrow,
                formattedSelectedDate: formattedSelectedDate,
                isPlanningTomorrow: isPlanningTomorrow,
                onOpenTasks: onOpenTasks,
                onReplanDay: onReplanDay,
                onPlanTomorrow: onPlanTomorrow,
                onSettings: onSettings
            )
            Text(formattedSelectedDate)
                .textStyleCaption()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let selectedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter
    }()

    private var formattedSelectedDate: String {
        Self.selectedDateFormatter.string(from: selectedCalendarDate)
    }

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else {
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var isSelectedToday: Bool {
        Calendar.current.isDateInToday(selectedCalendarDate)
    }

    private var isSelectedTomorrow: Bool {
        Calendar.current.isDateInTomorrow(selectedCalendarDate)
    }

    private func syncSelectedDay(from date: Date) {
        if Calendar.current.isDateInToday(date) {
            selectedDay = .today
        } else if Calendar.current.isDateInTomorrow(date) {
            selectedDay = .tomorrow
        }
    }

    private var viewFullTimelineLink: some View {
        Button(action: onViewTimeline) {
            Text("View full timeline")
                .textStyleCaption(color: DesignSystem.focus)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Clears the executive assistant sheet so content is fully scrollable.
    private var scrollBottomInset: CGFloat {
        ExecutiveAssistantMetrics.collapsedBottomPadding + DesignSystem.spacingMD
    }

    private var timelineDayPicker: some View {
        Picker("Day", selection: $selectedDay) {
            ForEach(TimelineDaySelection.allCases) { day in
                Text(day.rawValue).tag(day)
            }
        }
        .pickerStyle(.segmented)
    }

    private var tomorrowHeadsUpCard: some View {
        ElevatedSurface(padding: DesignSystem.spacingMD, emphasis: .subtle) {
            VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
                Label("Heads up", systemImage: "sunrise")
                    .font(.dsMetadata(weight: .semibold))
                    .foregroundColor(DesignSystem.accentPrimary)
                Text("Preview only. Tap Plan to shape tomorrow with your fixed blocks and flexible tasks.")
                    .font(.dsCaption())
                    .foregroundColor(DesignSystem.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct TodayHeaderBar: View {
    @ObservedObject var planningVM: ExecutivePlanningViewModel
    let isSelectedToday: Bool
    let isSelectedTomorrow: Bool
    let formattedSelectedDate: String
    let isPlanningTomorrow: Bool
    var onOpenTasks: () -> Void
    var onReplanDay: () -> Void
    var onPlanTomorrow: () -> Void
    var onSettings: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            Text(isSelectedToday ? "Today" : isSelectedTomorrow ? "Tomorrow" : formattedSelectedDate)
                .textStyleScreenTitle()

            Spacer()

            if isSelectedToday {
                Button(action: onOpenTasks) {
                    Label("All tasks", systemImage: "checklist")
                        .font(.dsCaption(weight: .semibold))
                        .foregroundColor(DesignSystem.textSecondary)
                        .padding(.horizontal, DesignSystem.spacingSM)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(DesignSystem.backgroundElevated))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("nav-all-tasks")
            }

            if isSelectedToday {
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
                .accessibilityLabel("Refresh timeline")
            } else if isSelectedTomorrow {
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

private struct TodayMultiDayBanner: View {
    @ObservedObject var planningVM: ExecutivePlanningViewModel
    @ObservedObject var tasksVM: TasksViewModel

    var body: some View {
        if let banner = planningVM.activeMultiDayBanner {
            multiDayBannerView(title: banner.title, dayIndex: banner.dayIndex, dayCount: banner.dayCount, sliceTitle: banner.sliceTitle)
        } else if let banner = TasksViewModel.activeMultiDayBanner(from: tasksVM.tasks) {
            multiDayBannerView(title: banner.title, dayIndex: banner.dayIndex, dayCount: banner.dayCount, sliceTitle: banner.sliceTitle)
        }
    }

    private func multiDayBannerView(title: String, dayIndex: Int, dayCount: Int, sliceTitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title) · day \(dayIndex) of \(dayCount)")
                .textStyleCaption(color: DesignSystem.focus)
            Text("Today: \(sliceTitle)")
                .textStyleCaption()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignSystem.spacingMD)
        .padding(.vertical, DesignSystem.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DesignSystem.focus.opacity(0.08))
        )
    }
}

// MARK: - Scroll performance: isolate @ObservedObject to leaf sections

private struct TodayPrioritiesSection: View {
    @ObservedObject var tasksVM: TasksViewModel
    @Binding var expandedPriorityId: String?
    var onOpenTasks: () -> Void
    var onStartTask: (LifeTask) -> Void
    var onEditTask: (LifeTask) -> Void
    var onCompleteTimelineTask: (String) -> Void

    @State private var cachedTopTasks: [LifeTask] = []
    @State private var tasksRevision: Int = 0

    var body: some View {
        LASectionCard(title: "Top Priorities", icon: "star.fill") {
            if cachedTopTasks.isEmpty {
                VStack(spacing: DesignSystem.spacingSM) {
                    Text("Nothing urgent. Add a task or capture a thought.")
                        .textStyleCaption()
                    Button(action: onOpenTasks) {
                        Text("Add a task")
                            .font(.system(size: 13, weight: .semibold, design: .default))
                            .foregroundColor(DesignSystem.accentPrimary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(spacing: DesignSystem.spacingSM) {
                    ForEach(cachedTopTasks) { task in
                        LAPriorityRow(
                            title: task.title,
                            category: task.lifeArea.rawValue,
                            detail: priorityDetail(for: task),
                            ringColor: priorityColor(for: task.lifeArea),
                            isComplete: task.status == .completed,
                            isActionsExpanded: expandedPriorityId == task.id,
                            onToggle: {
                                if task.status != .completed {
                                    onCompleteTimelineTask(task.id)
                                }
                            },
                            onToggleActions: {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    expandedPriorityId = expandedPriorityId == task.id ? nil : task.id
                                }
                            },
                            onStart: {
                                expandedPriorityId = nil
                                onStartTask(task)
                            },
                            onEdit: {
                                expandedPriorityId = nil
                                onEditTask(task)
                            }
                        )
                    }

                    Button(action: onOpenTasks) {
                        Text("View all tasks →")
                            .font(.system(size: 13, weight: .semibold, design: .default))
                            .foregroundColor(DesignSystem.accentPrimary)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, DesignSystem.spacingXS)
                }
            }
        }
        .accessibilityIdentifier("top-priorities")
        .onAppear { refreshTopTasks() }
        .onChange(of: tasksVM.tasks.count) { _, _ in refreshTopTasks() }
        .onChange(of: tasksRevision) { _, _ in refreshTopTasks() }
        .onReceive(tasksVM.objectWillChange) { _ in
            tasksRevision &+= 1
        }
    }

    private func refreshTopTasks() {
        cachedTopTasks = Array(
            tasksVM.activeTasks
                .sorted { $0.priority > $1.priority }
                .prefix(3)
        )
    }

    private static let scheduleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private func priorityDetail(for task: LifeTask) -> String {
        var parts: [String] = []
        if task.estimatedMinutes > 0 {
            parts.append(task.estimatedMinutes.durationString)
        }
        if let scheduled = task.scheduledTime ?? task.scheduledDate {
            let formatter = task.scheduledTime != nil ? Self.scheduleFormatter : Self.dayFormatter
            parts.append(formatter.string(from: scheduled))
        }
        parts.append(task.priority.label)
        return parts.joined(separator: " · ")
    }

    private func priorityColor(for area: LifeArea) -> Color {
        switch area {
        case .work: return DesignSystem.focus
        case .health, .medication, .hydration: return DesignSystem.health
        case .learning, .creativity: return DesignSystem.learning
        case .finance, .shopping: return DesignSystem.finance
        case .relationships: return DesignSystem.relationships
        case .travel: return DesignSystem.travel
        case .reflection, .personal, .home: return DesignSystem.reflection
        }
    }
}

private struct TodayScheduleSection: View {
    @ObservedObject var planningVM: ExecutivePlanningViewModel
    let isTomorrow: Bool
    let isPlanningTomorrow: Bool
    @ObservedObject var tasksVM: TasksViewModel
    var onViewTimeline: () -> Void
    var onPlanTomorrow: () -> Void
    var onCompleteTimelineTask: (String) -> Void
    var onRescheduleTimelineTask: (String) -> Void
    var onStartTask: (LifeTask) -> Void
    var onEditTask: (LifeTask) -> Void

    var body: some View {
        LASectionCard(
            title: "Schedule",
            subtitle: isTomorrow ? "Preview for tomorrow" : "Tap a task to start or edit",
            icon: "calendar"
        ) {
            if isTomorrow {
                ExecutiveLiveTimelineView(
                    rows: planningVM.tomorrowTimelineRows,
                    thinkingStep: nil,
                    isProcessing: false,
                    title: "",
                    emptyMessage: "Nothing on tomorrow's calendar yet.",
                    isPreview: true,
                    showPlanButton: true,
                    isPlanning: isPlanningTomorrow,
                    onViewAll: onViewTimeline,
                    onPlan: onPlanTomorrow
                )
            } else {
                ExecutiveLiveTimelineView(
                    rows: planningVM.timelineRows,
                    thinkingStep: planningVM.visibleThinkingStep,
                    isProcessing: planningVM.isProcessing,
                    title: "",
                    emptyMessage: "Your day fills in as you add tasks and commitments.",
                    onViewAll: onViewTimeline,
                    onCompleteTask: onCompleteTimelineTask,
                    onStartTask: { taskId in
                        if let task = task(for: taskId) { onStartTask(task) }
                    },
                    onEditTask: { taskId in
                        if let task = task(for: taskId) { onEditTask(task) }
                    },
                    onRescheduleTask: onRescheduleTimelineTask
                )
            }
        }
        .featureTourAnchor(.todayTimeline, cornerRadius: DesignSystem.radiusLG)
        .id(AppFeatureTourAnchorID.todayTimeline.rawValue)
    }

    private func task(for id: String) -> LifeTask? {
        tasksVM.tasks.first { $0.id == id }
            ?? tasksVM.completedToday.first { $0.id == id }
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
