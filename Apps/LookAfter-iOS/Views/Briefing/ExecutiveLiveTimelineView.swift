import SwiftUI
import LookAfterCore
import LookAfterFeatures

// MARK: - Timeline visual constants

private enum ExecutiveTimelineVisuals {
    static let gutterWidth: CGFloat = 28
    static let lineWidth: CGFloat = 2
    static let cardLeadingInset: CGFloat = 12
    static let rowSpacing: CGFloat = 14
    static let timeColumnWidth: CGFloat = 60
    static let rescheduleLeadingInset: CGFloat = timeColumnWidth + DesignSystem.spacingMD
    static let dotCompleted: CGFloat = 10
    static let dotUpcoming: CGFloat = 10
    static let dotCurrent: CGFloat = 14

    static let lime = DesignSystem.accentPrimary
    static let late = DesignSystem.late
    static let trackMuted = DesignSystem.textMuted.opacity(0.28)
    static let upcomingStroke = DesignSystem.textMuted.opacity(0.55)

    /// Card chrome — height comes from content, not duration.
    static let cardPadding: CGFloat = DesignSystem.spacingXS
    static let cardIconSize: CGFloat = 24
    static let cardContentSpacing: CGFloat = 4
    static let chevronHitSize: CGFloat = 28
}

private enum TimelineEventPhase {
    case completed
    case passed
    case current
    case upcoming
}

/// Bubbles LifeBlock vertical-drag state so parent ScrollViews can call `.scrollDisabled`.
struct TimelineBlockScrollDisabledKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

// MARK: - Live timeline

/// Continuous vertical progress timeline — Fitness / Linear style, not a card list.
struct ExecutiveLiveTimelineView: View {
    let rows: [ExecutivePlanningTimelineRow]
    let thinkingStep: String?
    let isProcessing: Bool
    var title: String = "Your Day"
    var emptyMessage: String = "Your timeline fills as the day takes shape."
    var isPreview: Bool = false
    var showPlanButton: Bool = false
    var isPlanning: Bool = false
    /// When set, only the first N rows render (Today Schedule preview).
    var maxVisibleRows: Int? = nil
    /// Hide the header “Full timeline” control (full sheet already shows the rail).
    var showsFullTimelineButton: Bool = true
    var onViewAll: () -> Void
    var onPlan: (() -> Void)?
    var onCapture: (() -> Void)?
    var onCompleteTask: ((String) -> Void)?
    var onUncompleteTask: ((String) -> Void)?
    var onStartTask: ((String) -> Void)?
    var onEditTask: ((String) -> Void)?
    var onRescheduleTask: ((String) -> Void)?
    var onRemoveFromTimelineTask: ((String) -> Void)?
    /// Persist a suggested display-only slot onto the real task.
    var onAddSuggestedTask: ((String, Date) -> Void)?
    var onPersistScheduleChange: ((LifeTask) -> Void)?
    var onScheduleDragCommitted: (() -> Void)?
    var taskForID: ((String) -> LifeTask?)?
    var parentScrollDisabled: Binding<Bool>?
    /// EventKit occupancy for drag guard (OccupiedDay).
    var calendarEventsProvider: ((Date) -> [BriefingCalendarEvent])? = nil

    @State private var completingTaskIds: Set<String> = []
    @State private var uncompletingTaskIds: Set<String> = []
    @State private var reschedulingTaskIds: Set<String> = []
    @State private var removingFromTimelineTaskIds: Set<String> = []
    @State private var expandedRowId: String?
    @StateObject private var constraintVM = TimelineConstraintViewModel()
    @State private var dragCoordinator = TimelineDragCoordinator()
    @State private var blockScrollDisabled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var displayRows: [ExecutivePlanningTimelineRow] {
        if let maxVisibleRows {
            return Array(rows.prefix(maxVisibleRows))
        }
        return rows
    }

    private var effectiveScrollDisabled: Binding<Bool> {
        if let parentScrollDisabled {
            return Binding(
                get: { blockScrollDisabled || parentScrollDisabled.wrappedValue },
                set: { newValue in
                    blockScrollDisabled = newValue
                    parentScrollDisabled.wrappedValue = newValue
                }
            )
        }
        return $blockScrollDisabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
            header

            if isProcessing, let step = thinkingStep {
                HStack(spacing: DesignSystem.spacingSM) {
                    ProgressView()
                        .scaleEffect(0.85)
                        .tint(ExecutiveTimelineVisuals.lime)
                    Text(step)
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textSecondary)
                }
                .padding(.vertical, DesignSystem.spacingXS)
            }

            if rows.isEmpty {
                emptyState
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    continuousTimeline(now: context.date)
                        .coordinateSpace(name: "timelineScroll")
                        .onPreferenceChange(TimelineDragAnchorKey.self) { dragCoordinator.updateAnchorY($0) }
                        .overlay {
                            TimelineDragTimeMeter(
                                proposedStart: dragCoordinator.proposedStart,
                                durationMinutes: dragCoordinator.durationMinutes,
                                anchorY: dragCoordinator.anchorY,
                                timeColumnWidth: ExecutiveTimelineVisuals.timeColumnWidth
                            )
                        }
                }
            }
        }
        .accessibilityIdentifier("screen-live-timeline")
        .onAppear {
            constraintVM.calendarEventsProvider = calendarEventsProvider
            seedConstraintState()
            constraintVM.onTaskUpdated = { task in
                onPersistScheduleChange?(task)
            }
            constraintVM.onScheduleDragCommitted = onScheduleDragCommitted
        }
        .onChange(of: rowConstraintSeed) { _, _ in seedConstraintState() }
    }

    /// Stable hash of row identity — avoids allocating `[String]` on every `body` for `onChange`.
    private var rowConstraintSeed: Int {
        var hasher = Hasher()
        for row in displayRows {
            hasher.combine(row.id)
            hasher.combine(row.taskId)
        }
        return hasher.finalize()
    }

    private func seedConstraintState() {
        for row in displayRows {
            guard let taskID = row.taskId else { continue }
            if let task = taskForID?(taskID) {
                constraintVM.upsert(task: task)
            } else if constraintVM.constraintsByTaskID[taskID] == nil {
                var stub = LifeTask(id: taskID, title: row.title, userId: "")
                stub.estimatedMinutes = row.estimatedMinutes ?? TaskDurationPolicy.minimumMinutes
                stub.applyTimeConstraint(row.timeConstraint)
                constraintVM.upsert(task: stub)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        Group {
            if !title.isEmpty || showPlanButton {
                HStack {
                    if !title.isEmpty {
                        Text(title)
                            .font(.dsHeadline())
                            .foregroundColor(DesignSystem.textPrimary)
                    }
                    Spacer()
                    if showPlanButton, let onPlan {
                        Button(action: onPlan) {
                            Group {
                                if isPlanning {
                                    ProgressView()
                                        .scaleEffect(0.75)
                                } else {
                                    Label("Plan", systemImage: "sparkles")
                                        .font(.dsCaption())
                                }
                            }
                            .padding(.horizontal, DesignSystem.spacingSM)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(LookAfterChrome.accentTint)
                        .disabled(isPlanning)
                    }
                    if !title.isEmpty, showsFullTimelineButton {
                        Button("Full timeline", action: onViewAll)
                            .font(.dsCaption())
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignSystem.spacingSM) {
            Text(emptyMessage)
                .font(.dsCaption())
                .foregroundColor(DesignSystem.textMuted)
            if let onCapture {
                Button(action: onCapture) {
                    Label("Capture a task or event", systemImage: "plus.circle.fill")
                        .font(.dsCaption(weight: .semibold))
                        .padding(.horizontal, DesignSystem.spacingMD)
                        .padding(.vertical, DesignSystem.spacingSM)
                }
                .buttonStyle(.glassProminent)
                .tint(LookAfterChrome.accentTint)
                .accessibilityIdentifier("timeline-capture-empty")
            }
        }
        .padding(.vertical, DesignSystem.spacingLG)
    }

    // MARK: - Continuous timeline (git-commit rail)

    private func continuousTimeline(now: Date) -> some View {
        let visible = displayRows
        let phases = rowPhases(visible)

        return LazyVStack(spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                gitRailRow(row: row, phase: phases[index], index: index, isLast: index == visible.count - 1, now: now)
            }
        }
    }

    @ViewBuilder
    private func gitRailRow(
        row: ExecutivePlanningTimelineRow,
        phase: TimelineEventPhase,
        index: Int,
        isLast: Bool,
        now: Date
    ) -> some View {
        let isCompleting = row.taskId.map { completingTaskIds.contains($0) } ?? false
        let isUncompleting = row.taskId.map { uncompletingTaskIds.contains($0) } ?? false
        let isRescheduling = row.taskId.map { reschedulingTaskIds.contains($0) } ?? false
        let isRemoving = row.taskId.map { removingFromTimelineTaskIds.contains($0) } ?? false

        HStack(alignment: .top, spacing: DesignSystem.spacingXS) {
            timelineTimeRail(for: row)
                .frame(width: ExecutiveTimelineVisuals.timeColumnWidth, alignment: .trailing)

            HStack(alignment: .top, spacing: ExecutiveTimelineVisuals.cardLeadingInset) {
                // Continuous spine behind dots: line runs through the gutter; markers sit on top.
                ZStack(alignment: .top) {
                    if !isLast {
                        Rectangle()
                            .fill(railSegmentColor(for: row, phase: phase))
                            .frame(width: ExecutiveTimelineVisuals.lineWidth)
                            .frame(maxHeight: .infinity)
                            .padding(.top, ExecutiveTimelineVisuals.dotUpcoming / 2)
                    }
                    TimelineDotView(phase: dotPhase(for: row, uiPhase: phase), isLate: row.isLate)
                }
                .frame(width: ExecutiveTimelineVisuals.gutterWidth)
                .frame(maxHeight: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: 0) {
                    interactiveBlock(for: row) {
                        EventTimelineCard(
                        row: row,
                        phase: phase,
                        now: now,
                        isCompleting: isCompleting,
                        isUncompleting: isUncompleting,
                        isRescheduling: isRescheduling,
                        isRemoving: isRemoving,
                        isActionsExpanded: expandedRowId == row.id,
                        showsTaskActions: row.taskId != nil && !row.isCompleted,
                        onToggleActions: {
                            withAnimation(PremiumMotion.spring(reduceMotion: reduceMotion)) {
                                expandedRowId = expandedRowId == row.id ? nil : row.id
                            }
                        },
                        onStart: row.taskId.flatMap { taskId in
                            guard let onStartTask else { return nil }
                            return {
                                expandedRowId = nil
                                onStartTask(taskId)
                            }
                        },
                        onEdit: row.taskId.flatMap { taskId in
                            guard let onEditTask else { return nil }
                            return {
                                expandedRowId = nil
                                onEditTask(taskId)
                            }
                        },
                        onDoubleTapComplete: row.taskId.flatMap { taskId in
                            if row.isCompleted {
                                guard let onUncompleteTask else { return nil }
                                return {
                                    withAnimation(PremiumMotion.spring(reduceMotion: reduceMotion)) {
                                        uncompletingTaskIds.insert(taskId)
                                        onUncompleteTask(taskId)
                                    }
                                    Task {
                                        try? await Task.sleep(nanoseconds: 600_000_000)
                                        uncompletingTaskIds.remove(taskId)
                                    }
                                }
                            }
                            guard let onCompleteTask else { return nil }
                            return {
                                withAnimation(PremiumMotion.spring(reduceMotion: reduceMotion)) {
                                    completingTaskIds.insert(taskId)
                                    onCompleteTask(taskId)
                                }
                                Task {
                                    try? await Task.sleep(nanoseconds: 600_000_000)
                                    completingTaskIds.remove(taskId)
                                }
                            }
                        },
                        onReschedule: row.canReschedule ? row.taskId.flatMap { taskId in
                            guard let onRescheduleTask else { return nil }
                            return {
                                reschedulingTaskIds.insert(taskId)
                                onRescheduleTask(taskId)
                                Task {
                                    try? await Task.sleep(nanoseconds: 800_000_000)
                                    reschedulingTaskIds.remove(taskId)
                                }
                            }
                        } : nil,
                        onRemoveFromTimeline: row.canRemoveFromTimeline ? row.taskId.flatMap { taskId in
                            guard let onRemoveFromTimelineTask else { return nil }
                            return {
                                removingFromTimelineTaskIds.insert(taskId)
                                expandedRowId = nil
                                onRemoveFromTimelineTask(taskId)
                                Task {
                                    try? await Task.sleep(nanoseconds: 800_000_000)
                                    removingFromTimelineTaskIds.remove(taskId)
                                }
                            }
                        } : nil,
                        onAddSuggested: {
                            guard row.isSuggestedSlot,
                                  let sourceId = row.suggestedSourceTaskId,
                                  let start = row.suggestedStart,
                                  let onAddSuggestedTask else { return nil }
                            return {
                                onAddSuggestedTask(sourceId, start)
                            }
                        }()
                    )
                }
                    if !isLast {
                        Color.clear
                            .frame(height: ExecutiveTimelineVisuals.rowSpacing + gapPadding(after: index))
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(PremiumMotion.spring(reduceMotion: reduceMotion), value: row.isCompleted)
        .animation(PremiumMotion.spring(reduceMotion: reduceMotion), value: isCompleting)
    }

    @ViewBuilder
    private func timelineTimeRail(for row: ExecutivePlanningTimelineRow) -> some View {
        let isMuted = row.isCompleted || row.isPast
        VStack(alignment: .trailing, spacing: 2) {
            if row.isSuggestedSlot {
                Text(row.timeLabel)
                    .font(.dsCaption())
                    .foregroundStyle(DesignSystem.textMuted)
            } else if !row.timeLabel.isEmpty {
                Text(row.timeLabel)
                    .font(.dsCaption(weight: row.isUnslottedFlexible ? .medium : .semibold))
                    .foregroundStyle(
                        isMuted
                            ? DesignSystem.textMuted
                            : (row.isUnslottedFlexible ? DesignSystem.textMuted : DesignSystem.textSecondary)
                    )
            } else if row.isUnslottedFlexible {
                Text("Flexible")
                    .font(.dsCaption(weight: .medium))
                    .foregroundStyle(DesignSystem.textMuted)
            } else {
                Text("—")
                    .font(.dsCaption())
                    .foregroundStyle(DesignSystem.textMuted)
            }

            if !row.endTimeLabel.isEmpty {
                Text(row.endTimeLabel)
                    .font(.dsCaption())
                    .foregroundStyle(DesignSystem.textMuted)
            }

            timelineConstraintMicroBadge(for: row)
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func timelineConstraintMicroBadge(for row: ExecutivePlanningTimelineRow) -> some View {
        if row.isSuggestedSlot {
            Text("Suggested")
                .font(.dsCaption(weight: .semibold))
                .foregroundStyle(DesignSystem.textMuted)
        } else if row.isUnslottedFlexible {
            // Time column already shows "Flexible" — skip duplicate badge.
            EmptyView()
        } else if row.timeConstraint == .flexible, !row.isFixedEvent {
            Text("Flexible")
                .font(.dsCaption(weight: .semibold))
                .foregroundStyle(DesignSystem.textMuted)
        } else if row.timeConstraint == .fluid {
            Text("Fluid")
                .font(.dsCaption(weight: .semibold))
                .foregroundStyle(DesignSystem.textMuted.opacity(0.85))
        } else if row.timeConstraint == .anchored || row.isFixedEvent {
            Image(systemName: "lock.fill")
                .font(.dsCaption(weight: .bold))
                .foregroundStyle(DesignSystem.textMuted)
        }
    }

    @ViewBuilder
    private func interactiveBlock<Content: View>(
        for row: ExecutivePlanningTimelineRow,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if let taskID = row.taskId, !row.isCompleted, !isPreview, !row.isSuggestedSlot {
            let resolved = constraintVM.constraintsByTaskID[taskID] ?? row.timeConstraint
            LifeBlockView(
                taskID: taskID,
                constraint: resolved,
                baselineStart: row.sortDate,
                isEnabled: !row.isFixedEvent,
                viewModel: constraintVM,
                dragCoordinator: dragCoordinator,
                scrollDisabled: effectiveScrollDisabled
            ) {
                content()
            }
            .preference(key: TimelineBlockScrollDisabledKey.self, value: blockScrollDisabled)
        } else {
            content()
        }
    }

    private func dotPhase(for row: ExecutivePlanningTimelineRow, uiPhase: TimelineEventPhase) -> TimelineEventPhase {
        if row.isCompleted { return .completed }
        if uiPhase == .passed { return .passed }
        if uiPhase == .current { return .current }
        return .upcoming
    }

    private func gapPadding(after index: Int) -> CGFloat {
        let visible = displayRows
        guard index + 1 < visible.count else { return 0 }
        let current = visible[index]
        let next = visible[index + 1]
        if current.isUnslottedFlexible || next.isUnslottedFlexible { return 0 }
        let end = current.sortDate.addingTimeInterval(TimeInterval((current.estimatedMinutes ?? 30) * 60))
        let gapMinutes = max(0, next.sortDate.timeIntervalSince(end) / 60)
        return min(48, CGFloat(gapMinutes / 15) * 4)
    }

    private func railSegmentColor(for row: ExecutivePlanningTimelineRow, phase: TimelineEventPhase) -> Color {
        switch phase {
        case .completed, .passed:
            return ExecutiveTimelineVisuals.lime.opacity(0.85)
        case .current:
            return row.isLate
                ? ExecutiveTimelineVisuals.late.opacity(0.55)
                : ExecutiveTimelineVisuals.lime.opacity(0.45)
        case .upcoming:
            return ExecutiveTimelineVisuals.trackMuted
        }
    }

    // MARK: - Phase logic

    private func rowPhases(_ rows: [ExecutivePlanningTimelineRow]) -> [TimelineEventPhase] {
        guard !rows.isEmpty else { return [] }

        var phases = rows.map { row -> TimelineEventPhase in
            if row.isCompleted { return .completed }
            if row.isPast { return .passed }
            return .upcoming
        }

        if let currentIndex = rows.firstIndex(where: { $0.isNow && !$0.isCompleted }) {
            phases[currentIndex] = .current
        }

        return phases
    }
}

// MARK: - Dot

private struct TimelineDotView: View {
    let phase: TimelineEventPhase
    var isLate: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color {
        isLate && phase == .current ? ExecutiveTimelineVisuals.late : ExecutiveTimelineVisuals.lime
    }

    var body: some View {
        ZStack {
            switch phase {
            case .completed:
                Circle()
                    .fill(ExecutiveTimelineVisuals.lime)
                    .frame(width: ExecutiveTimelineVisuals.dotCompleted + 2, height: ExecutiveTimelineVisuals.dotCompleted + 2)
                Image(systemName: "checkmark")
                    .font(.dsCaption(weight: .bold))
                    .foregroundColor(Color.black.opacity(0.85))
                    .symbolEffect(.bounce, value: phase)
                    .symbolEffectsRemoved(reduceMotion)

            case .passed:
                Circle()
                    .fill(ExecutiveTimelineVisuals.lime.opacity(0.55))
                    .frame(width: ExecutiveTimelineVisuals.dotCompleted, height: ExecutiveTimelineVisuals.dotCompleted)

            case .current:
                Circle()
                    .fill(accent.opacity(0.25))
                    .frame(width: ExecutiveTimelineVisuals.dotCurrent + 10, height: ExecutiveTimelineVisuals.dotCurrent + 10)

                Circle()
                    .fill(accent)
                    .frame(width: ExecutiveTimelineVisuals.dotCurrent, height: ExecutiveTimelineVisuals.dotCurrent)
                    .shadow(color: accent.opacity(0.45), radius: 6)

            case .upcoming:
                Circle()
                    .strokeBorder(ExecutiveTimelineVisuals.upcomingStroke, lineWidth: 2)
                    .background(Circle().fill(DesignSystem.backgroundPrimary))
                    .frame(width: ExecutiveTimelineVisuals.dotUpcoming, height: ExecutiveTimelineVisuals.dotUpcoming)
            }
        }
        .frame(width: ExecutiveTimelineVisuals.gutterWidth, height: dotRowHeight)
    }

    private var dotRowHeight: CGFloat {
        phase == .current ? 28 : 22
    }
}

// MARK: - Event card (offset from rail)

private struct EventTimelineCard: View {
    let row: ExecutivePlanningTimelineRow
    let phase: TimelineEventPhase
    var now: Date = Date()
    var isCompleting: Bool = false
    var isUncompleting: Bool = false
    var isRescheduling: Bool = false
    var isRemoving: Bool = false
    var isActionsExpanded: Bool = false
    var showsTaskActions: Bool = false
    var onToggleActions: (() -> Void)?
    var onStart: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDoubleTapComplete: (() -> Void)?
    var onReschedule: (() -> Void)?
    var onRemoveFromTimeline: (() -> Void)?
    var onAddSuggested: (() -> Void)?

    @Environment(\.timelineBlockIsDragging) private var isBlockDragging
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Auction-filled casualty — brief sparkle ("I found this time for you").
    private var isResurrectedSparkle: Bool {
        guard let id = row.taskId else { return false }
        return ResurrectedTaskRegistry.shared.isResurrected(id)
    }

    private var nowAccent: Color {
        row.isLate ? ExecutiveTimelineVisuals.late : ExecutiveTimelineVisuals.lime
    }

    /// Height follows real content — not estimated minutes.
    private var hasSecondaryContent: Bool {
        if isActionsExpanded { return true }
        if row.isSuggestedSlot { return true }
        if !row.detailLines.isEmpty { return true }
        if !row.subtitle.isEmpty, !row.isUnslottedFlexible { return true }
        if row.isCompleted, row.completedAt != nil { return true }
        return false
    }

    private var showsTimingRow: Bool {
        if phase == .current, !row.isCompleted { return true }
        if showsDurationMetadata { return true }
        if row.isSuggestedSlot, !row.scheduleRangeLabel.isEmpty { return true }
        if row.isCompleted, row.completedAt != nil { return true }
        if !row.isCompleted, row.change != .unchanged { return true }
        return false
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.calendar = .current
        formatter.timeZone = Calendar.current.timeZone
        return formatter
    }()

    private var nowClockString: String {
        Self.timeFormatter.string(from: now)
    }

    /// View-only countdown for the active block; does not alter scheduling math.
    private var remainingMinutesString: String? {
        guard phase == .current, !row.isCompleted else { return nil }
        let durationMinutes = row.estimatedMinutes ?? 0
        guard durationMinutes > 0 else { return nil }
        let end = row.sortDate.addingTimeInterval(TimeInterval(durationMinutes * 60))
        let remaining = max(0, Int(ceil(end.timeIntervalSince(now) / 60.0)))
        return "\(remaining)m left"
    }

    private var titleWithStatusAccessibilityLabel: String {
        let title = TaskTitleDisplay.humanized(row.title)
        if row.isCompleted {
            return "\(title), DONE"
        }
        if phase == .current {
            return "\(title), \(row.isLate ? "LATE" : "NOW")"
        }
        if phase == .passed {
            return "\(title), Passed"
        }
        return title
    }

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.spacingSM) {
            categoryIcon

            VStack(alignment: .leading, spacing: ExecutiveTimelineVisuals.cardContentSpacing) {
                // Row 1 — title + compact status chip (NOW stays here so timing row stays narrow).
                HStack(alignment: .center, spacing: 8) {
                    Text(TaskTitleDisplay.humanized(row.title))
                        .font(.dsBody())
                        .fontWeight(phase == .current && !row.isCompleted ? .semibold : .regular)
                        .foregroundColor(titleColor)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(titleWithStatusAccessibilityLabel)

                    titleStatusTrailing
                }

                // Row 2 — clock / remaining / duration only.
                if showsTimingRow {
                    timingRow
                }

                if hasSecondaryContent, !row.subtitle.isEmpty, !row.isUnslottedFlexible {
                    Text(row.subtitle)
                        .font(.dsCaption())
                        .foregroundColor(row.isCompleted ? DesignSystem.textMuted : DesignSystem.textSecondary)
                        .lineLimit(2)
                }

                if hasSecondaryContent, !row.detailLines.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(row.detailLines, id: \.self) { line in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(DesignSystem.textMuted.opacity(0.35))
                                    .frame(width: 3, height: 3)
                                Text(line)
                                    .font(.dsCaption())
                                    .foregroundColor(DesignSystem.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                if row.isSuggestedSlot, let onAddSuggested {
                    Button(action: onAddSuggested) {
                        Label("Add to day", systemImage: "plus.circle.fill")
                            .font(.dsCaption(weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignSystem.spacingSM)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(LookAfterChrome.accentTint)
                    .accessibilityIdentifier("timeline-add-suggested")
                    .padding(.top, DesignSystem.spacingXS)
                }

                if isActionsExpanded, showsTaskActions {
                VStack(spacing: DesignSystem.spacingSM) {
                    if let onStart {
                        Button(action: onStart) {
                            Label("Start now", systemImage: "play.fill")
                                .font(.dsCaption(weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DesignSystem.spacingSM)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(LookAfterChrome.accentTint)
                        .accessibilityIdentifier("focus-start-now")
                    }
                    if let onEdit {
                        Button(action: onEdit) {
                            Label("Edit task", systemImage: "pencil")
                                .font(.dsCaption(weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DesignSystem.spacingSM)
                        }
                        .buttonStyle(.glass)
                    }
                    if row.canReschedule, let onReschedule {
                        Button(action: onReschedule) {
                            HStack(spacing: 6) {
                                if isRescheduling {
                                    ProgressView()
                                        .scaleEffect(0.75)
                                        .tint(ExecutiveTimelineVisuals.lime)
                                } else {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.dsCaption(weight: .semibold))
                                }
                                Text(row.isPast ? "Reschedule to next open slot" : "Reschedule")
                                    .font(.dsCaption(weight: .semibold))
                            }
                            .foregroundColor(ExecutiveTimelineVisuals.lime)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignSystem.spacingSM)
                            .background(
                                Capsule().fill(ExecutiveTimelineVisuals.lime.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isRescheduling)
                    }
                    if row.canRemoveFromTimeline, let onRemoveFromTimeline {
                        Button(action: onRemoveFromTimeline) {
                            HStack(spacing: 6) {
                                if isRemoving {
                                    ProgressView()
                                        .scaleEffect(0.75)
                                        .tint(DesignSystem.warning)
                                } else {
                                    Image(systemName: "calendar.badge.minus")
                                        .font(.dsCaption(weight: .semibold))
                                }
                                Text("Remove from timeline")
                                    .font(.dsCaption(weight: .semibold))
                            }
                            .foregroundColor(DesignSystem.warning)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignSystem.spacingSM)
                            .background(
                                Capsule().fill(DesignSystem.warning.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isRemoving)
                    }
                }
                .padding(.top, DesignSystem.spacingXS)
                .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(ExecutiveTimelineVisuals.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                .stroke(
                    isActionsExpanded
                        ? DesignSystem.accentPrimary.opacity(0.35)
                        : borderColor,
                    lineWidth: row.isConflict ? 2 : (phase == .current || isActionsExpanded ? 1 : 0.5)
                )
        )
        .overlay {
            if isResurrectedSparkle {
                ResurrectedSparkleOverlay()
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous))
                    .allowsHitTesting(false)
                    .accessibilityLabel("Resurrected into free time")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous))
        .opacity(row.isCompleted ? 0.72 : ((isCompleting || isUncompleting || isRescheduling || isRemoving) ? 0.55 : 1))
        .scaleEffect((isCompleting || isUncompleting || isRescheduling || isRemoving) ? 0.98 : 1)
        .animation(PremiumMotion.spring(reduceMotion: reduceMotion), value: row.isCompleted)
        .animation(PremiumMotion.spring(reduceMotion: reduceMotion), value: isCompleting)
        .contentShape(RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous))
        .onTapGesture(count: 2) {
            guard !isBlockDragging else { return }
            onDoubleTapComplete?()
        }
        .accessibilityIdentifier(row.taskId.map { "timeline-event-card-\($0)" } ?? "timeline-event-card")
        .accessibilityAction(named: row.isCompleted ? "Mark incomplete" : "Mark complete") {
            onDoubleTapComplete?()
        }
        .accessibilityHint(accessibilityHint)
    }

    private var accessibilityHint: String {
        var parts: [String] = []
        if onDoubleTapComplete != nil {
            parts.append(
                row.isCompleted
                    ? "Double tap to mark this task incomplete."
                    : "Double tap to mark this task complete."
            )
        }
        if row.canReschedule {
            parts.append("Use Pick up to reschedule, then drag up or down. New time announces when you drop.")
        }
        if row.isSuggestedSlot {
            parts.append("Suggested slot. Use Add to day to place it on your schedule.")
        }
        return parts.joined(separator: " ")
    }

    /// Compact status + chevron on the title row (keeps timing row from overflowing).
    @ViewBuilder
    private var titleStatusTrailing: some View {
        HStack(spacing: 6) {
            if row.isCompleted {
                statusChip("DONE", foreground: ExecutiveTimelineVisuals.lime, background: ExecutiveTimelineVisuals.lime.opacity(0.15))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .accessibilityHidden(true)
                Image(systemName: "checkmark.circle.fill")
                    .font(.dsBody(weight: .semibold))
                    .foregroundColor(ExecutiveTimelineVisuals.lime)
                    .symbolEffect(.bounce, value: row.isCompleted)
                    .symbolEffectsRemoved(reduceMotion)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if phase == .current {
                statusChip(
                    row.isLate ? "LATE" : "NOW",
                    foreground: nowAccent,
                    background: nowAccent.opacity(0.15)
                )
                .accessibilityHidden(true)
            } else if phase == .passed {
                statusChip("Passed", foreground: ExecutiveTimelineVisuals.lime.opacity(0.85), background: ExecutiveTimelineVisuals.lime.opacity(0.12))
                    .accessibilityHidden(true)
            }

            if showsTaskActions, let onToggleActions {
                Button(action: onToggleActions) {
                    Image(systemName: isActionsExpanded ? "chevron.up.circle" : "chevron.down.circle")
                        .font(.dsCaption(weight: .medium))
                        .foregroundColor(DesignSystem.textMuted)
                        .frame(
                            width: ExecutiveTimelineVisuals.chevronHitSize,
                            height: ExecutiveTimelineVisuals.chevronHitSize
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isActionsExpanded ? "Collapse actions" : "Expand actions")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
    }

    private var showsDurationMetadata: Bool {
        row.estimatedMinutes != nil && (row.estimatedMinutes ?? 0) > 0
    }

    /// Clock / remaining / duration — second row only (no NOW chip; that sits with the title).
    private var timingRow: some View {
        HStack(alignment: .center, spacing: 8) {
            if phase == .current, !row.isCompleted {
                Text(nowClockString)
                    .font(.dsCaption(weight: .semibold))
                    .foregroundStyle(nowAccent)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(PremiumMotion.snappy(reduceMotion: reduceMotion), value: nowClockString)
                    .accessibilityLabel("Current time \(nowClockString)")
                if let remainingMinutesString {
                    Text(remainingMinutesString)
                        .font(.dsCaption(weight: .medium))
                        .foregroundStyle(nowAccent.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(PremiumMotion.snappy(reduceMotion: reduceMotion), value: remainingMinutesString)
                        .accessibilityLabel(remainingMinutesString)
                }
            }

            if showsDurationMetadata, let minutes = row.estimatedMinutes, minutes > 0 {
                metadataItem(icon: "hourglass", text: minutes.durationString)
            }

            if row.isSuggestedSlot, !row.scheduleRangeLabel.isEmpty {
                metadataItem(icon: "sparkles", text: row.scheduleRangeLabel)
            }

            if row.isCompleted, let completedAt = row.completedAt {
                metadataItem(
                    icon: "checkmark.circle",
                    text: "Done \(Self.timeFormatter.string(from: completedAt))"
                )
            }

            if !row.isCompleted, row.change != .unchanged {
                deltaBadge(for: row.change)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusChip(_ label: String, foreground: Color, background: Color) -> some View {
        Text(label)
            .font(.dsCaption(weight: .bold))
            .foregroundColor(foreground)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(background))
    }

    private func metadataItem(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.dsCaption(weight: .semibold))
            Text(text)
                .font(.dsCaption(weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .contentTransition(.numericText())
                .animation(PremiumMotion.snappy(reduceMotion: reduceMotion), value: text)
        }
        .foregroundColor(row.isCompleted ? DesignSystem.textMuted : DesignSystem.textSecondary)
    }

    private var categoryIcon: some View {
        let size = ExecutiveTimelineVisuals.cardIconSize
        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(row.isCompleted ? ExecutiveTimelineVisuals.lime.opacity(0.2) : DesignSystem.backgroundElevated)
                .frame(width: size, height: size)
            Image.safeSystemName(row.icon, fallback: row.kind.icon)
                .font(.dsCaption(weight: .semibold))
                .foregroundStyle(row.isCompleted ? ExecutiveTimelineVisuals.lime : DesignSystem.textSecondary)
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityLabel(row.kind.sectionLabel)
    }

    private var titleColor: Color {
        if row.isCompleted { return DesignSystem.textMuted }
        if row.isPast { return DesignSystem.textPrimary.opacity(0.75) }
        switch phase {
        case .completed: return DesignSystem.textMuted
        case .passed: return DesignSystem.textPrimary.opacity(0.75)
        case .current: return DesignSystem.textPrimary
        case .upcoming: return DesignSystem.textPrimary.opacity(0.92)
        }
    }

    private var cardBackground: some ShapeStyle {
        if row.isConflict {
            return AnyShapeStyle(DesignSystem.warning.opacity(0.12))
        }
        switch phase {
        case .current:
            return AnyShapeStyle(DesignSystem.contentSurfaceElevated)
        case .completed, .passed:
            return AnyShapeStyle(DesignSystem.contentSurfaceSubtle)
        case .upcoming:
            return AnyShapeStyle(DesignSystem.contentSurface)
        }
    }

    private var borderColor: Color {
        if row.isConflict { return DesignSystem.warning.opacity(0.75) }
        if phase == .current {
            return nowAccent.opacity(0.4)
        }
        return DesignSystem.divider
    }

    @ViewBuilder
    private func deltaBadge(for change: PlanningTimelineChange) -> some View {
        let (label, color): (String, Color) = {
            switch change {
            case .added: return ("Added", ExecutiveTimelineVisuals.lime)
            case .moved: return ("Moved", .blue)
            case .reused: return ("Kept", .green)
            case .removed: return ("Removed", .red)
            case .conflict: return ("Conflict", DesignSystem.warning)
            case .unchanged: return ("", .clear)
            }
        }()
        if !label.isEmpty {
            Text(label)
                .font(.dsCaption(weight: .semibold))
                .foregroundColor(color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(color.opacity(0.12)))
        }
    }
}

/// Soft shimmer for auction-resurrected blocks — temporary "I found this time" cue.
private struct ResurrectedSparkleOverlay: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
            .stroke(
                DesignSystem.accentPrimary.opacity(pulse ? 0.55 : 0.2),
                lineWidth: 1.5
            )
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                    .fill(DesignSystem.accentPrimary.opacity(pulse ? 0.08 : 0.03))
            )
            .overlay(alignment: .topTrailing) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DesignSystem.accentPrimary.opacity(0.85))
                    .padding(8)
            }
            .onAppear {
                guard !reduceMotion else {
                    pulse = true
                    return
                }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

#if DEBUG
/// One block of each time constraint for rapid visual QA.
enum TimelineConstraintPreviewProvider {
    static var rows: [ExecutivePlanningTimelineRow] {
        let now = Date()
        return [
            ExecutivePlanningTimelineRow(
                id: "preview-anchored",
                sortDate: now,
                timeLabel: "9:00 AM",
                endTimeLabel: "9:30 AM",
                title: "Team standup",
                subtitle: "Anchored meeting",
                kind: .meeting,
                isNow: true,
                taskId: "task-anchored",
                estimatedMinutes: 30,
                isFixedEvent: true,
                timeConstraint: .anchored
            ),
            ExecutivePlanningTimelineRow(
                id: "preview-flexible",
                sortDate: now.addingTimeInterval(3600),
                timeLabel: "10:00 AM",
                endTimeLabel: "11:30 AM",
                title: "Deep work block",
                subtitle: "Flexible preferred slot",
                kind: .work,
                taskId: "task-flexible",
                estimatedMinutes: 90,
                timeConstraint: .flexible
            ),
            ExecutivePlanningTimelineRow(
                id: "preview-fluid",
                sortDate: now.addingTimeInterval(7200),
                timeLabel: "Afternoon",
                endTimeLabel: "",
                title: "Pick up groceries",
                subtitle: "Fluid soft intent",
                kind: .shopping,
                taskId: "task-fluid",
                estimatedMinutes: 40,
                timeConstraint: .fluid
            ),
        ]
    }
}

#Preview("Constraint physics") {
    ScrollView {
        ExecutiveLiveTimelineView(
            rows: TimelineConstraintPreviewProvider.rows,
            thinkingStep: nil,
            isProcessing: false,
            title: "Constraint demo",
            onViewAll: {}
        )
        .padding()
    }
    .background(DesignSystem.backgroundPrimary)
}
#endif
