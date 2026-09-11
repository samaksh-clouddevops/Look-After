import SwiftUI
import Combine
import LookAfterCore
import LookAfterFeatures
#if canImport(UIKit)
import UIKit
#endif

/// Today — full timeline; planning opens from the header Plan control as a sheet.
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
    var onPostWake: () -> Void = {}
    var onGoingOut: () -> Void = {}
    var onRefresh: () async -> Void
    var onPlanningSubmit: (_ text: String, _ startedWithVoice: Bool) -> Void
    var onNegotiationSelect: (String) -> Void
    var onApprovePendingPlan: () -> Void = {}
    var onRejectPendingPlan: () -> Void = {}
    var onProactiveBannerAppear: (ProactiveAction) -> Void = { _ in }
    var onRedesignWithAI: (String) -> Void = { _ in }
    var onOpenSleepDetail: () -> Void = {}
    var onOpenHealthDetail: () -> Void = {}
    var onOpenMedication: () -> Void = {}
    var onCompleteTimelineTask: (String) -> Void = { _ in }
    var onUncompleteTimelineTask: (String) -> Void = { _ in }
    var onRescheduleTimelineTask: (String) -> Void = { _ in }
    var onRemoveFromTimelineTask: (String) -> Void = { _ in }
    var onStartTask: (LifeTask) -> Void = { _ in }
    var onEditTask: (LifeTask) -> Void = { _ in }
    var onCapture: () -> Void = {}
    var isPlanningTomorrow: Bool = false

    @State private var selectedDay: TimelineDaySelection = .today
    @State private var selectedMetricKind: TodayMetricKind?
    @State private var selectedCalendarDate = Calendar.current.startOfDay(for: Date())
    @State private var expandedPriorityId: String?
    @State private var timelineBlockScrollDisabled = false
    @State private var showPlanningAssistant = false
    @State private var planningSheetDetent: PresentationDetent = .medium
    @State private var showDayControls = false

    var body: some View {
        timelineSection
            .onAppear {
            planningVM.bootstrapTimeline(from: lifeTimelineEvents)
            planningVM.bootstrapTomorrowTimeline(from: tomorrowLifeTimelineEvents)
            refreshPreWindowFitIfNeeded()
            planningVM.seedProactiveSuggestionsIfNeeded(from: briefingVM.proactiveActions)
            Task {
                await briefingVM.refreshDayAudit(tasksVM: tasksVM)
            }
        }
        .onChange(of: briefingVM.proactiveActions.count) { _, _ in
            refreshProactiveIfNeeded()
        }
        .sheet(item: $selectedMetricKind) { kind in
            TodayMetricDetailSheet(
                kind: kind,
                briefingVM: briefingVM,
                capacity: briefingVM.executiveCapacity,
                weatherSnapshot: weatherSnapshot
            )
        }
        .sheet(isPresented: $showPlanningAssistant) {
            ExecutiveAssistantSheet(
                planningVM: planningVM,
                speechManager: speechManager,
                speechSynthesizer: speechSynthesizer,
                onSubmit: onPlanningSubmit,
                onNegotiationSelect: onNegotiationSelect,
                onApprovePendingPlan: onApprovePendingPlan,
                onRejectPendingPlan: onRejectPendingPlan,
                onRedesignWithAI: onRedesignWithAI,
                onPostWake: onPostWake,
                onGoingOut: onGoingOut
            )
            .presentationDetents([.medium, .large], selection: $planningSheetDetent)
            .presentationDragIndicator(.visible)
            .presentationCompactAdaptation(.sheet)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .onAppear { planningSheetDetent = .medium }
            #if canImport(UIKit)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                planningSheetDetent = .large
            }
            #endif
        }
        .accessibilityIdentifier("screen-today")
        .onChange(of: selectedDay) { _, _ in
            refreshPreWindowFitIfNeeded()
            refreshProactiveIfNeeded()
        }
    }

    private func refreshPreWindowFitIfNeeded() {
        guard isSelectedToday else {
            cachedPreWindowFit = nil
            return
        }
        cachedPreWindowFit = PreWindowFitAnalyzer.analyze(tasks: tasksVM.schedulingContext)
    }

    private func refreshProactiveIfNeeded() {
        guard isSelectedToday else {
            cachedProactiveAction = nil
            return
        }
        cachedProactiveAction = TodayCoachSlot.pickCoachAction(from: briefingVM.proactiveActions)
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

    @State private var cachedPreWindowFit: PreWindowFitAnalyzer.Result?
    @State private var cachedProactiveAction: ProactiveAction?

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
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: DesignSystem.spacingLG, pinnedViews: []) {
                    todayHeader

                    if showDayControls {
                        dayControlsPanel
                    }

                    if isSelectedToday {
                        TodayMultiDayBanner(planningVM: planningVM, tasksVM: tasksVM)
                        // Critical coach only above hero (overcommit / transition). Micro-start goes below.
                        // Hide when Plan sheet is open so Open plan isn't duplicated (LAY-P2).
                        if !showPlanningAssistant {
                            TodayCoachSlot(
                                tasksVM: tasksVM,
                                briefingVM: briefingVM,
                                cachedFit: $cachedPreWindowFit,
                                cachedAction: $cachedProactiveAction,
                                placement: .aboveHero,
                                onReplan: onReplanDay,
                                onSelectOption: onNegotiationSelect,
                                onBannerAppear: onProactiveBannerAppear
                            )
                            // Avoid stacking negotiation with the coach card (same message twice).
                            if cachedPreWindowFit?.isOvercommitted != true,
                               cachedProactiveAction.map({ TodayCoachSlot.isTransitionKind($0.kind) }) != true {
                                TodayInlineNegotiationSection(
                                    planningVM: planningVM,
                                    onSelectOption: onNegotiationSelect
                                )
                            }
                        }
                        TodayDoThisNowSection(
                            tasksVM: tasksVM,
                            planningVM: planningVM,
                            onStartTask: onStartTask
                        )
                        .id(Self.todayHeroScrollID)
                        if !showPlanningAssistant {
                            TodayCoachSlot(
                                tasksVM: tasksVM,
                                briefingVM: briefingVM,
                                cachedFit: $cachedPreWindowFit,
                                cachedAction: $cachedProactiveAction,
                                placement: .belowHero,
                                onReplan: onReplanDay,
                                onSelectOption: onNegotiationSelect,
                                onBannerAppear: onProactiveBannerAppear
                            )
                        }
                        TodayPrioritiesSection(
                            tasksVM: tasksVM,
                            planningVM: planningVM,
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
                            timelineScrollDisabled: $timelineBlockScrollDisabled,
                            onViewTimeline: onViewTimeline,
                            onPlanTomorrow: onPlanTomorrow,
                            onCompleteTimelineTask: onCompleteTimelineTask,
                            onUncompleteTimelineTask: onUncompleteTimelineTask,
                            onRescheduleTimelineTask: onRescheduleTimelineTask,
                            onRemoveFromTimelineTask: onRemoveFromTimelineTask,
                            onStartTask: onStartTask,
                            onEditTask: onEditTask,
                            onCapture: onCapture
                        )
                        // V5: Gate full EOD journal until evening; keep a quiet expand earlier.
                        TodayEndOfDayGate(
                            modulesVM: modulesVM,
                            tasksVM: tasksVM,
                            speechManager: speechManager
                        )
                    } else if isSelectedTomorrow {
                        tomorrowHeadsUpCard
                        TodayScheduleSection(
                            planningVM: planningVM,
                            isTomorrow: true,
                            isPlanningTomorrow: isPlanningTomorrow,
                            tasksVM: tasksVM,
                            timelineScrollDisabled: $timelineBlockScrollDisabled,
                            onViewTimeline: onViewTimeline,
                            onPlanTomorrow: onPlanTomorrow,
                            onCompleteTimelineTask: onCompleteTimelineTask,
                            onUncompleteTimelineTask: onUncompleteTimelineTask,
                            onRescheduleTimelineTask: onRescheduleTimelineTask,
                            onRemoveFromTimelineTask: onRemoveFromTimelineTask,
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
            .scrollDisabled(timelineBlockScrollDisabled)
            .scrollViewScrollLock(timelineBlockScrollDisabled)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .onPreferenceChange(TimelineBlockScrollDisabledKey.self) { timelineBlockScrollDisabled = $0 }
            .refreshable {
                await onRefresh()
            }
            .onAppear {
                scrollTodayToHero(using: proxy, animated: false)
                // Second pass after LazyVStack / hero resolve (FLOW-T1).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    scrollTodayToHero(using: proxy, animated: false)
                }
            }
            .onChange(of: showPlanningAssistant) { _, isOpen in
                if !isOpen { scrollTodayToHero(using: proxy) }
            }
            .onChange(of: selectedDay) { _, _ in
                scrollTodayToHero(using: proxy)
            }
            .onChange(of: planningVM.nowTaskId) { _, _ in
                scrollTodayToHero(using: proxy, animated: false)
            }
            .onChange(of: planningVM.timelineRows.map { "\($0.id):\($0.isNow):\($0.isLate)" }.joined(separator: "|")) { _, _ in
                scrollTodayToHero(using: proxy, animated: false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .tourScrollToAnchor)) { note in
                guard let raw = note.userInfo?[TourScrollUserInfoKey.anchorID] as? String else { return }
                if raw == AppFeatureTourAnchorID.todayTimeline.rawValue {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(AppFeatureTourAnchorID.todayTimeline.rawValue, anchor: .center)
                    }
                } else if raw == AppFeatureTourAnchorID.todayAssistant.rawValue {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(AppFeatureTourAnchorID.todayAssistant.rawValue, anchor: .top)
                    }
                }
            }
        }
    }

    private static let todayHeroScrollID = "today-hero-top"

    private func scrollTodayToHero(using proxy: ScrollViewProxy, animated: Bool = true) {
        guard isSelectedToday else { return }
        let scroll = {
            proxy.scrollTo(Self.todayHeroScrollID, anchor: .top)
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.28), scroll)
        } else {
            scroll()
        }
    }

    private var todayHeader: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            TodayHeaderBar(
                planningVM: planningVM,
                isSelectedToday: isSelectedToday,
                isSelectedTomorrow: isSelectedTomorrow,
                formattedSelectedDate: formattedSelectedDate,
                isPlanningTomorrow: isPlanningTomorrow,
                showDayControls: $showDayControls,
                onOpenTasks: onOpenTasks,
                onOpenPlan: { showPlanningAssistant = true },
                onReplanDay: onReplanDay,
                onPlanTomorrow: onPlanTomorrow,
                onSettings: onSettings
            )
            if !showDayControls {
                Text(formattedSelectedDate)
                    .textStyleCaption()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dayControlsPanel: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            Text(formattedSelectedDate)
                .textStyleCaption()
            LAWeekDateStrip(
                days: weekDays,
                selectedDate: $selectedCalendarDate
            )
            .onChange(of: selectedCalendarDate) { _, newDate in
                syncSelectedDay(from: newDate)
            }
            if isSelectedToday {
                TodayContextQuickActions(onPostWake: onPostWake, onGoingOut: onGoingOut)
            }
        }
        .accessibilityIdentifier("today-day-controls")
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

    /// Extra scroll clearance above the floating tab bar so End of day isn’t clipped.
    private var scrollBottomInset: CGFloat {
        DesignSystem.BriefingViewport.scrollBottomClearance
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

private struct TodayContextQuickActions: View {
    var onPostWake: () -> Void
    var onGoingOut: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.spacingSM) {
                quietContextButton(title: "I just woke up", icon: "sun.max.fill", action: onPostWake)
                quietContextButton(title: "Going out", icon: "figure.walk", action: onGoingOut)
            }
        }
    }

    /// Quieter than toolbar glass — secondary context only.
    private func quietContextButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.dsCaption(weight: .medium))
            }
            .foregroundStyle(DesignSystem.textSecondary)
            .padding(.horizontal, DesignSystem.spacingSM)
            .frame(minHeight: DesignSystem.minTouchTarget)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(DesignSystem.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct TodayHeaderBar: View {
    @ObservedObject var planningVM: ExecutivePlanningViewModel
    let isSelectedToday: Bool
    let isSelectedTomorrow: Bool
    let formattedSelectedDate: String
    let isPlanningTomorrow: Bool
    @Binding var showDayControls: Bool
    var onOpenTasks: () -> Void
    var onOpenPlan: () -> Void
    var onReplanDay: () -> Void
    var onPlanTomorrow: () -> Void
    var onSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: LAChromeMetrics.toolbarGap) {
            Text(isSelectedToday ? "Today" : isSelectedTomorrow ? "Tomorrow" : formattedSelectedDate)
                .textStyleScreenTitle()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)

            Spacer(minLength: DesignSystem.spacingSM)

            if isSelectedToday {
                Button(action: onOpenPlan) {
                    Label("Plan", systemImage: "sparkles")
                        .font(.dsCaption(weight: .semibold))
                        .foregroundStyle(DesignSystem.accentPrimary)
                        .frame(minHeight: DesignSystem.minTouchTarget)
                        .padding(.horizontal, DesignSystem.spacingSM)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Plan")
                .accessibilityIdentifier("nav-plan-assistant")
                .featureTourAnchor(.todayAssistant, cornerRadius: 18)
                .id(AppFeatureTourAnchorID.todayAssistant.rawValue)

                Menu {
                    Button(
                        showDayControls ? "Hide day controls" : "Day controls",
                        systemImage: showDayControls ? "calendar.badge.checkmark" : "calendar"
                    ) {
                        showDayControls.toggle()
                    }
                    .accessibilityIdentifier("nav-day-controls")

                    Button("All tasks", systemImage: "checklist", action: onOpenTasks)
                        .accessibilityIdentifier("nav-all-tasks")
                    Button("Refresh timeline", systemImage: "arrow.triangle.2.circlepath") {
                        onReplanDay()
                    }
                    .disabled(planningVM.isReplanning || planningVM.isProcessing)
                    Button("Settings", systemImage: "gearshape", action: onSettings)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.dsIcon())
                        .foregroundStyle(DesignSystem.textPrimary)
                        .frame(width: DesignSystem.minTouchTarget, height: DesignSystem.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More")
                .accessibilityIdentifier("nav-today-overflow")
                .featureTourAnchor(.todayAllTasks, cornerRadius: 18)
                .id(AppFeatureTourAnchorID.todayAllTasks.rawValue)
            } else if isSelectedTomorrow {
                Button(action: onPlanTomorrow) {
                    Group {
                        if isPlanningTomorrow {
                            ProgressView()
                                .scaleEffect(0.75)
                        } else {
                            Label("Plan", systemImage: "sparkles")
                                .font(.dsCaption(weight: .semibold))
                        }
                    }
                    .frame(height: DesignSystem.minTouchTarget)
                    .padding(.horizontal, DesignSystem.spacingSM)
                }
                .buttonStyle(.glassProminent)
                .tint(LookAfterChrome.accentTint)
                .disabled(isPlanningTomorrow)
                .accessibilityLabel("Plan tomorrow with AI")

                LAToolbarIconButton(
                    systemName: "gearshape",
                    accessibilityLabel: "Settings",
                    action: onSettings
                )
            } else {
                LAToolbarIconButton(
                    systemName: "gearshape",
                    accessibilityLabel: "Settings",
                    action: onSettings
                )
            }
        }
    }
}

/// Negotiation chips stay in the scroll when Plan sheet is closed — never a second dock.
private struct TodayInlineNegotiationSection: View {
    @ObservedObject var planningVM: ExecutivePlanningViewModel
    let onSelectOption: (String) -> Void

    var body: some View {
        Group {
            if let negotiation = planningVM.negotiation {
                negotiationCard(negotiation)
            } else if let multiDay = planningVM.multiDayPlanning {
                negotiationCard(multiDay)
            }
        }
    }

    private func negotiationCard(_ negotiation: PlanningNegotiation) -> some View {
        // V2 on Today: never a filled primary above the hero — prefer quiet Open plan.
        let primary: String? = {
            if let openPlan = negotiation.options.first(where: { $0.localizedCaseInsensitiveContains("open plan") }) {
                return openPlan
            }
            return negotiation.options.first
        }()
        let secondary = negotiation.options.filter { $0 != primary }

        return VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            Text(negotiation.question)
                .font(.dsCaption())
                .foregroundStyle(DesignSystem.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DesignSystem.spacingSM) {
                if let primary {
                    Button {
                        HapticManager.impact(.medium)
                        onSelectOption(primary)
                    } label: {
                        Text(primary)
                            .font(.dsCaption(weight: .semibold))
                            .foregroundStyle(DesignSystem.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .padding(.horizontal, DesignSystem.spacingMD)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: DesignSystem.minTouchTarget)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(DesignSystem.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                if !secondary.isEmpty {
                    Menu {
                        ForEach(secondary, id: \.self) { option in
                            Button(option) {
                                HapticManager.impact(.medium)
                                onSelectOption(option)
                            }
                        }
                    } label: {
                        Text("More")
                            .font(.dsCaption(weight: .semibold))
                            .foregroundStyle(DesignSystem.textSecondary)
                            .padding(.horizontal, DesignSystem.spacingMD)
                            .frame(minWidth: 72)
                            .frame(minHeight: DesignSystem.minTouchTarget)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(DesignSystem.border, lineWidth: 1)
                            )
                    }
                    .accessibilityLabel("More planning options")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .elevatedSurface(padding: DesignSystem.spacingMD, cornerRadius: DesignSystem.radiusMD)
        .accessibilityIdentifier("banner-inline-negotiation")
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

/// Single coach surface: overcommit > transition above hero; micro-start below hero.
private struct TodayCoachSlot: View {
    enum Placement {
        case aboveHero
        case belowHero
    }

    @ObservedObject var tasksVM: TasksViewModel
    @ObservedObject var briefingVM: DailyBriefingViewModel
    @Binding var cachedFit: PreWindowFitAnalyzer.Result?
    @Binding var cachedAction: ProactiveAction?
    var placement: Placement = .aboveHero
    let onReplan: () -> Void
    let onSelectOption: (String) -> Void
    let onBannerAppear: (ProactiveAction) -> Void

    @State private var lastAnnouncedKey: String?

    var body: some View {
        Group {
            switch placement {
            case .aboveHero:
                if let fit = cachedFit, fit.isOvercommitted {
                    PreWindowFitBanner(result: fit, onReplan: onReplan)
                } else if let action = coachAction, Self.isTransitionKind(action.kind) {
                    ProactiveActionBanner(
                        action: action,
                        emphasizesPrimary: false,
                        onSelectOption: onSelectOption
                    )
                }
            case .belowHero:
                if cachedFit?.isOvercommitted != true,
                   let action = coachAction,
                   Self.isMicroStartKind(action.kind) {
                    ProactiveActionBanner(
                        action: action,
                        emphasizesPrimary: false,
                        onSelectOption: onSelectOption
                    )
                }
            }
        }
        .onAppear { refresh() }
        .onChange(of: tasksVM.tasksContentRevision) { _, _ in refresh() }
        .onChange(of: briefingVM.proactiveActions.count) { _, _ in refresh() }
        .onChange(of: announcementKey(for: coachAction)) { _, key in
            guard let action = coachAction, let key, key != lastAnnouncedKey else { return }
            lastAnnouncedKey = key
            onBannerAppear(action)
        }
    }

    private var coachAction: ProactiveAction? {
        guard cachedFit?.isOvercommitted != true else { return nil }
        return cachedAction
    }

    private func announcementKey(for action: ProactiveAction?) -> String? {
        guard let action else { return nil }
        return "\(action.kind.rawValue)|\(action.message)"
    }

    private func refresh() {
        cachedFit = PreWindowFitAnalyzer.analyze(tasks: tasksVM.schedulingContext)
        cachedAction = Self.pickCoachAction(from: briefingVM.proactiveActions)
    }

    /// Prefer transition / time-critical, then micro-start; skip generic schedule noise.
    static func pickCoachAction(from actions: [ProactiveAction]) -> ProactiveAction? {
        let candidates = actions.filter { $0.surface == .banner || $0.surface == .autoApplyPreview || $0.severity == .high || $0.severity == .medium }
        let pool = candidates.isEmpty ? actions : candidates

        if let transition = pool.first(where: { isTransitionKind($0.kind) }) {
            return transition
        }
        if let micro = pool.first(where: { isMicroStartKind($0.kind) }) {
            return micro
        }
        return nil
    }

    static func isTransitionKind(_ kind: ProactiveAction.Kind) -> Bool {
        switch kind {
        case .transitionShield, .calendarChange, .overwhelmCircuitBreaker, .hyperfocusBreak:
            return true
        default:
            return false
        }
    }

    static func isMicroStartKind(_ kind: ProactiveAction.Kind) -> Bool {
        switch kind {
        case .initiationBridge, .waitingMode:
            return true
        default:
            return false
        }
    }
}

private struct TodayDoThisNowSection: View {
    @ObservedObject var tasksVM: TasksViewModel
    @ObservedObject var planningVM: ExecutivePlanningViewModel
    var onStartTask: (LifeTask) -> Void

    /// Live rail NOW — do not cache in @State (F05 race: tasks/timeline land after first appear).
    private var heroTask: LifeTask? {
        if let nowId = planningVM.nowTaskId,
           let resolved = tasksVM.resolveTimelineTask(id: nowId),
           resolved.status.isActive {
            return resolved
        }
        if let nowRow = planningVM.timelineRows.first(where: { $0.isNow && !$0.isCompleted }),
           let id = nowRow.taskId,
           let resolved = tasksVM.resolveTimelineTask(id: id),
           resolved.status.isActive {
            return resolved
        }
        if let lateRow = planningVM.timelineRows.first(where: { $0.isLate && !$0.isCompleted }),
           let id = lateRow.taskId,
           let resolved = tasksVM.resolveTimelineTask(id: id),
           resolved.status.isActive {
            return resolved
        }
        return TaskListSorter.sortByNextActionableThenPriority(tasksVM.activeTasks).first
    }

    var body: some View {
        Group {
            if let task = heroTask {
                TodayRecommendedHeroCard(
                    content: Self.heroContent(for: task, isLate: isLate(for: task)),
                    durationLabel: Self.durationLabel(for: task),
                    onPrimaryAction: { onStartTask(task) }
                )
                .accessibilityIdentifier("today-do-this-now")
            }
        }
    }

    private func isLate(for task: LifeTask) -> Bool {
        planningVM.timelineRows.first(where: { $0.taskId == task.id })?.isLate == true
    }

    private static func heroContent(for task: LifeTask, isLate: Bool) -> CalmHeroContent {
        let minutes = TaskDurationPolicy.microStartSessionMinutes(for: task)
        let supporting = Self.supportingLine(for: task, isLate: isLate)
        return CalmHeroContent(
            title: TaskTitleDisplay.humanized(task.title),
            supportingLine: supporting,
            metadataLine: nil,
            primaryActionTitle: TaskDurationPolicy.microStartOptionLabel(for: task),
            disclosure: CalmHeroDisclosure(
                narrative: nil,
                whyLines: [
                    isLate
                        ? "This block is overdue — still your timeline NOW until you finish or reschedule it."
                        : "This is your timeline NOW (clocks, not the AI review).",
                    "\(minutes)-min start matches this task’s estimate."
                ]
            )
        )
    }

    private static func durationLabel(for task: LifeTask) -> String {
        let minutes = TaskDurationPolicy.microStartSessionMinutes(for: task)
        return "\(minutes)m focus"
    }

    private static let scheduleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static func supportingLine(for task: LifeTask, isLate: Bool) -> String {
        var parts: [String] = []
        if isLate {
            parts.append("Overdue")
        }
        let day = Calendar.current.startOfDay(for: Date())
        switch TaskScheduleInterval.displaySchedule(for: task, on: day) {
        case .unslottedFlexible:
            parts.append("Flexible today")
        case .window(let start, _, _):
            parts.append(scheduleFormatter.string(from: start))
        case .noSchedule:
            break
        }
        if task.estimatedMinutes > 0 {
            parts.append(task.estimatedMinutes.durationString)
        }
        parts.append(task.lifeArea.shortLabel)
        return parts.joined(separator: " · ")
    }
}

private struct TodayPrioritiesSection: View {
    @ObservedObject var tasksVM: TasksViewModel
    @ObservedObject var planningVM: ExecutivePlanningViewModel
    @Binding var expandedPriorityId: String?
    var onOpenTasks: () -> Void
    var onStartTask: (LifeTask) -> Void
    var onEditTask: (LifeTask) -> Void
    var onCompleteTimelineTask: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var topTasks: [LifeTask] {
        let heroId = planningVM.nowTaskId
            ?? planningVM.timelineRows.first(where: { ($0.isNow || $0.isLate) && !$0.isCompleted })?.taskId
        let sorted = TaskListSorter.sortByNextActionableThenPriority(tasksVM.activeTasks)
        return Array(sorted.filter { $0.id != heroId }.prefix(2))
    }

    var body: some View {
        LASectionCard(title: "Up next", icon: "star.fill") {
            if topTasks.isEmpty {
                VStack(spacing: DesignSystem.spacingSM) {
                    Text("Nothing urgent. Add a task or capture a thought.")
                        .textStyleCaption()
                    Button(action: onOpenTasks) {
                        Text("Add a task")
                            .font(.dsCaption(weight: .semibold))
                            .foregroundColor(DesignSystem.accentPrimary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(spacing: DesignSystem.spacingSM) {
                    ForEach(topTasks) { task in
                        LAPriorityRow(
                            title: TaskTitleDisplay.humanized(task.title),
                            category: task.lifeArea.shortLabel,
                            detail: priorityDetail(for: task),
                            ringColor: DesignSystem.textSecondary,
                            isComplete: task.status == .completed,
                            isActionsExpanded: expandedPriorityId == task.id,
                            onToggle: {
                                if task.status != .completed {
                                    withAnimation(PremiumMotion.spring(reduceMotion: reduceMotion)) {
                                        onCompleteTimelineTask(task.id)
                                    }
                                }
                            },
                            onToggleActions: {
                                withAnimation(PremiumMotion.spring(reduceMotion: reduceMotion)) {
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
                            .font(.dsCaption(weight: .semibold))
                            .foregroundColor(DesignSystem.accentPrimary)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, DesignSystem.spacingXS)
                }
            }
        }
        .accessibilityIdentifier("top-priorities")
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
        let day = Calendar.current.startOfDay(for: Date())
        switch TaskScheduleInterval.displaySchedule(for: task, on: day) {
        case .unslottedFlexible:
            parts.append("Flexible")
        case .window(let start, _, _):
            parts.append(Self.scheduleFormatter.string(from: start))
        case .noSchedule:
            if let scheduled = task.scheduledDate {
                parts.append(Self.dayFormatter.string(from: scheduled))
            }
        }
        if task.estimatedMinutes > 0 {
            parts.append(task.estimatedMinutes.durationString)
        }
        parts.append(task.priority.label)
        return parts.joined(separator: " · ")
    }
}

private struct TodayScheduleSection: View {
    @ObservedObject var planningVM: ExecutivePlanningViewModel
    let isTomorrow: Bool
    let isPlanningTomorrow: Bool
    @ObservedObject var tasksVM: TasksViewModel
    @Binding var timelineScrollDisabled: Bool
    var onViewTimeline: () -> Void
    var onPlanTomorrow: () -> Void
    var onCompleteTimelineTask: (String) -> Void
    var onUncompleteTimelineTask: (String) -> Void
    var onRescheduleTimelineTask: (String) -> Void
    var onRemoveFromTimelineTask: (String) -> Void
    var onStartTask: (LifeTask) -> Void
    var onEditTask: (LifeTask) -> Void
    var onCapture: () -> Void = {}

    @AppStorage(TimelineDragHint.dismissedKey) private var dragHintDismissed = false

    private static let previewRowLimit = 2

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
            LASectionCard(
                title: "Schedule",
                subtitle: scheduleSubtitle,
                icon: "calendar"
            ) {
                scheduleContent
            }
            .featureTourAnchor(.todayTimeline, cornerRadius: DesignSystem.radiusLG)
            .id(AppFeatureTourAnchorID.todayTimeline.rawValue)

            if showsDragHint {
                Text("Press and hold a task, then drag up or down to set its start time.")
                    .textStyleCaption(color: DesignSystem.textSecondary)
                    .accessibilityIdentifier("timeline-drag-hint")
            }

            if !isTomorrow, !previewRows.isEmpty {
                Button(action: onViewTimeline) {
                    Text(hasMoreThanPreview ? "Full timeline →" : "View full timeline")
                        .font(.dsCaption(weight: .semibold))
                        .foregroundColor(DesignSystem.accentPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today-schedule-full-timeline")
            }
        }
    }

    private var scheduleSubtitle: String {
        if isTomorrow { return "Preview for tomorrow" }
        return "Next on your day"
    }

    private var previewRows: [ExecutivePlanningTimelineRow] {
        Array(planningVM.timelineRows.filter { !$0.isCompleted }.prefix(Self.previewRowLimit))
    }

    private var hasMoreThanPreview: Bool {
        planningVM.timelineRows.filter { !$0.isCompleted }.count > Self.previewRowLimit
    }

    private var hasMovableRows: Bool {
        planningVM.timelineRows.contains(where: \.canReschedule)
    }

    private var showsDragHint: Bool {
        !isTomorrow && !dragHintDismissed && hasMovableRows
    }

    @ViewBuilder
    private var scheduleContent: some View {
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
                rows: previewRows,
                thinkingStep: planningVM.visibleThinkingStep,
                isProcessing: planningVM.isProcessing,
                title: "",
                emptyMessage: "Your day fills in as you add tasks and commitments.",
                maxVisibleRows: Self.previewRowLimit,
                onViewAll: onViewTimeline,
                onCapture: onCapture,
                onCompleteTask: onCompleteTimelineTask,
                onUncompleteTask: onUncompleteTimelineTask,
                onStartTask: { taskId in
                    Task { await startResolvedTask(id: taskId) }
                },
                onEditTask: { taskId in
                    Task { await editResolvedTask(id: taskId) }
                },
                onRescheduleTask: onRescheduleTimelineTask,
                onRemoveFromTimelineTask: onRemoveFromTimelineTask,
                onAddSuggestedTask: { sourceId, start in
                    Task { await addSuggestedSlot(sourceId: sourceId, start: start) }
                },
                onPersistScheduleChange: { task in
                    Task { await persistResolvedSchedule(task) }
                },
                onScheduleDragCommitted: {
                    dragHintDismissed = true
                },
                taskForID: { id in tasksVM.resolveTimelineTask(id: id) },
                parentScrollDisabled: $timelineScrollDisabled,
                calendarEventsProvider: tasksVM.calendarEventsProvider
            )
        }
    }

    private func startResolvedTask(id: String) async {
        guard var task = tasksVM.resolveTimelineTask(id: id) else { return }
        let userId = task.userId.isEmpty
            ? (tasksVM.tasks.first?.userId ?? "")
            : task.userId
        if id.hasPrefix("proj-"), !userId.isEmpty {
            do {
                task = try await tasksVM.materializeTimelineTask(task, userId: userId)
            } catch {
                return
            }
        }
        onStartTask(task)
    }

    private func editResolvedTask(id: String) async {
        guard var task = tasksVM.resolveTimelineTask(id: id) else { return }
        let userId = task.userId.isEmpty
            ? (tasksVM.tasks.first?.userId ?? "")
            : task.userId
        if id.hasPrefix("proj-"), !userId.isEmpty {
            do {
                task = try await tasksVM.materializeTimelineTask(task, userId: userId)
            } catch {
                return
            }
        }
        onEditTask(task)
    }

    private func persistResolvedSchedule(_ task: LifeTask) async {
        var toSave = task
        let userId = task.userId.isEmpty
            ? (tasksVM.tasks.first?.userId ?? "")
            : task.userId
        guard !userId.isEmpty else { return }
        if task.id.hasPrefix("proj-")
            || !tasksVM.tasks.contains(where: { $0.id == task.id }) {
            do {
                toSave = try await tasksVM.materializeTimelineTask(task, userId: userId)
            } catch {
                return
            }
        }
        await tasksVM.scheduleMutation.persist(
            toSave,
            userId: userId,
            userPlaced: true
        )
    }

    private func addSuggestedSlot(sourceId: String, start: Date) async {
        guard let resolved = tasksVM.resolveTimelineTask(id: sourceId) else { return }
        let userId = resolved.userId.isEmpty
            ? (tasksVM.tasks.first?.userId ?? "")
            : resolved.userId
        guard !userId.isEmpty else { return }
        _ = await tasksVM.scheduleMutation.placeSuggestedSlot(
            taskID: sourceId,
            start: start,
            userId: userId
        )
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
                    .font(.largeTitle.weight(.bold))
                    .foregroundColor(DesignSystem.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
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
            VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
                Label("DO THIS NOW", systemImage: "star.fill")
                    .font(.dsMetadata(weight: .semibold))
                    .foregroundColor(DesignSystem.accentPrimary)
                    .labelStyle(.titleAndIcon)

                Text(content.title)
                    .font(.dsHeadline(weight: .bold))
                    .foregroundColor(DesignSystem.textPrimary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                if let supporting = content.supportingLine, !supporting.isEmpty {
                    Text(supporting)
                        .font(.dsCaption())
                        .foregroundColor(
                            supporting.hasPrefix("Overdue")
                                ? DesignSystem.late
                                : DesignSystem.textSecondary
                        )
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let durationLabel, !durationLabel.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.dsCaption())
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TodayWhyAffordance: View {
    let content: CalmHeroContent
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.22)) { isExpanded.toggle() }
            }, label: {
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
                .frame(minHeight: DesignSystem.minTouchTarget)
                .contentShape(Rectangle())
            })
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
                        .fill(DesignSystem.contentSurface)
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

// MARK: - Pre-window fit

private struct ProactiveActionBanner: View {
    let action: ProactiveAction
    /// When false, primary uses quiet glass so hero Start remains the loudest CTA.
    var emphasizesPrimary: Bool = true
    let onSelectOption: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            HStack(spacing: DesignSystem.spacingSM) {
                Image(systemName: bannerIcon)
                    .foregroundColor(action.severity == .high ? .orange : DesignSystem.focus)
                Text(bannerTitle)
                    .font(.dsBody(weight: .semibold))
                    .foregroundColor(DesignSystem.textPrimary)
            }
            Text(action.message)
                .font(.dsCaption())
                .foregroundColor(DesignSystem.textSecondary)
                .dsPrimaryText(lineLimit: 4)

            // Quiet coach (V2): prefer "Open plan" as the visible outline CTA.
            // Loud / sheet surfaces keep options[0] (V3: "I'm ready") as filled primary.
            let primary: String? = {
                if !emphasizesPrimary,
                   let openPlan = action.options.first(where: { $0.localizedCaseInsensitiveContains("open plan") }) {
                    return openPlan
                }
                return action.options.first
            }()
            let secondary = action.options.filter { $0 != primary }

            HStack(spacing: DesignSystem.spacingSM) {
                if let primary {
                    if emphasizesPrimary {
                        Button(action: { onSelectOption(primary) }) {
                            Text(primary)
                                .font(.dsBody(weight: .semibold))
                                .foregroundStyle(DesignSystem.accentOnPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .padding(.horizontal, DesignSystem.spacingMD)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: DesignSystem.minTouchTarget)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(LookAfterChrome.accentTint)
                    } else {
                        Button(action: { onSelectOption(primary) }) {
                            Text(primary)
                                .font(.dsCaption(weight: .semibold))
                                .foregroundStyle(DesignSystem.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .padding(.horizontal, DesignSystem.spacingMD)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: DesignSystem.minTouchTarget)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(DesignSystem.border, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !secondary.isEmpty {
                    Menu {
                        ForEach(secondary, id: \.self) { option in
                            Button(option) { onSelectOption(option) }
                        }
                    } label: {
                        Text("More")
                            .font(.dsCaption(weight: .semibold))
                            .foregroundStyle(DesignSystem.textSecondary)
                            .padding(.horizontal, DesignSystem.spacingMD)
                            .frame(minWidth: 72)
                            .frame(minHeight: DesignSystem.minTouchTarget)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(DesignSystem.border, lineWidth: 1)
                            )
                    }
                    .accessibilityLabel("More options")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .elevatedSurface(padding: DesignSystem.spacingMD, cornerRadius: DesignSystem.radiusMD)
        .accessibilityIdentifier("banner-proactive-suggestion")
    }

    private var bannerTitle: String {
        switch action.kind {
        case .calendarChange: return "Calendar update"
        case .waitingMode: return "Quick win window"
        case .transitionShield: return "Transition soon"
        case .initiationBridge: return "Micro-start"
        case .hyperfocusBreak, .overwhelmCircuitBreaker: return "Check-in"
        default: return "Schedule check"
        }
    }

    private var bannerIcon: String {
        switch action.kind {
        case .calendarChange, .transitionShield, .overwhelmCircuitBreaker:
            return "exclamationmark.triangle.fill"
        case .initiationBridge, .waitingMode:
            return "bolt.fill"
        default:
            return "lightbulb.fill"
        }
    }
}

private struct PreWindowFitBanner: View {
    let result: PreWindowFitAnalyzer.Result
    let onReplan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            HStack(spacing: DesignSystem.spacingSM) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Crunch before \(result.anchor.title)")
                    .font(.dsBody(weight: .semibold))
                    .foregroundColor(DesignSystem.textPrimary)
            }
            Text(result.summaryLine)
                .font(.dsCaption())
                .foregroundColor(DesignSystem.textSecondary)
                .dsPrimaryText(lineLimit: 4)
            Button(action: onReplan) {
                Text("Replan with AI")
                    .font(.dsCaption(weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.spacingSM)
            }
            .buttonStyle(.glassProminent)
            .tint(LookAfterChrome.accentTint)
        }
        .elevatedSurface(padding: DesignSystem.spacingMD, cornerRadius: DesignSystem.radiusMD)
        .accessibilityIdentifier("banner-pre-window-fit")
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
