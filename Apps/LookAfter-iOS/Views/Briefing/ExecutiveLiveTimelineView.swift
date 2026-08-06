import SwiftUI
import LookAfterCore
import LookAfterFeatures

// MARK: - Timeline visual constants

private enum ExecutiveTimelineVisuals {
    static let gutterWidth: CGFloat = 28
    static let lineWidth: CGFloat = 2
    static let cardLeadingInset: CGFloat = 12
    static let rowSpacing: CGFloat = 14
    static let timeColumnWidth: CGFloat = 56
    static let rescheduleLeadingInset: CGFloat = timeColumnWidth + DesignSystem.spacingMD
    static let dotCompleted: CGFloat = 10
    static let dotUpcoming: CGFloat = 10
    static let dotCurrent: CGFloat = 14

    static let lime = DesignSystem.accentPrimary
    static let trackMuted = DesignSystem.textMuted.opacity(0.28)
    static let upcomingStroke = DesignSystem.textMuted.opacity(0.55)
}

private enum TimelineEventPhase {
    case completed
    case passed
    case current
    case upcoming
}

// MARK: - Dot position preference

private struct TimelineDotCenterKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
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
    var onViewAll: () -> Void
    var onPlan: (() -> Void)?
    var onCompleteTask: ((String) -> Void)?
    var onUncompleteTask: ((String) -> Void)?
    var onStartTask: ((String) -> Void)?
    var onEditTask: ((String) -> Void)?
    var onRescheduleTask: ((String) -> Void)?

    @State private var dotCenters: [String: CGFloat] = [:]
    @State private var railHeight: CGFloat = 0
    @State private var completingTaskIds: Set<String> = []
    @State private var uncompletingTaskIds: Set<String> = []
    @State private var reschedulingTaskIds: Set<String> = []
    @State private var expandedRowId: String?
    @StateObject private var constraintVM = TimelineConstraintViewModel()
    @State private var blockScrollDisabled = false

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
                continuousTimeline
            }
        }
        .accessibilityIdentifier("screen-live-timeline")
        .onAppear { seedConstraintState() }
        .onChange(of: rows.map(\.id)) { _, _ in seedConstraintState() }
    }

    private func seedConstraintState() {
        // Shadow rows into VM so swipe mutations have a constraint source even before tasks load.
        for row in rows {
            guard let taskID = row.taskId else { continue }
            if constraintVM.constraintsByTaskID[taskID] == nil {
                var stub = LifeTask(id: taskID, title: row.title, userId: "")
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
                                        .tint(DesignSystem.accentPrimary)
                                } else {
                                    Label("Plan", systemImage: "sparkles")
                                        .font(.dsCaption())
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isPlanning)
                        .foregroundColor(DesignSystem.accentPrimary)
                    }
                    if !title.isEmpty {
                        Button("Full timeline", action: onViewAll)
                            .font(.dsCaption())
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        Text(emptyMessage)
            .font(.dsCaption())
            .foregroundColor(DesignSystem.textMuted)
            .padding(.vertical, DesignSystem.spacingLG)
    }

    // MARK: - Continuous timeline (git-commit rail)

    private var continuousTimeline: some View {
        let phases = rowPhases(rows)

        return LazyVStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                gitRailRow(row: row, phase: phases[index], index: index, isLast: index == rows.count - 1)
            }
        }
    }

    @ViewBuilder
    private func gitRailRow(
        row: ExecutivePlanningTimelineRow,
        phase: TimelineEventPhase,
        index: Int,
        isLast: Bool
    ) -> some View {
        let isCompleting = row.taskId.map { completingTaskIds.contains($0) } ?? false
        let isUncompleting = row.taskId.map { uncompletingTaskIds.contains($0) } ?? false
        let isRescheduling = row.taskId.map { reschedulingTaskIds.contains($0) } ?? false

        HStack(alignment: .top, spacing: ExecutiveTimelineVisuals.cardLeadingInset) {
            VStack(spacing: 0) {
                TimelineDotView(phase: dotPhase(for: row, uiPhase: phase))

                if !isLast {
                    Rectangle()
                        .fill(railSegmentColor(for: row, phase: phase))
                        .frame(width: ExecutiveTimelineVisuals.lineWidth)
                        .frame(maxHeight: .infinity)
                        .frame(minHeight: 24)
                }
            }
            .frame(width: ExecutiveTimelineVisuals.gutterWidth)

            VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                interactiveBlock(for: row) {
                    EventTimelineCard(
                        row: row,
                        phase: phase,
                        isCompleting: isCompleting,
                        isUncompleting: isUncompleting,
                        isRescheduling: isRescheduling,
                        isActionsExpanded: expandedRowId == row.id,
                        showsTaskActions: row.taskId != nil && !row.isCompleted,
                        onToggleActions: {
                            withAnimation(.easeInOut(duration: 0.22)) {
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
                                    uncompletingTaskIds.insert(taskId)
                                    onUncompleteTask(taskId)
                                    Task {
                                        try? await Task.sleep(nanoseconds: 600_000_000)
                                        uncompletingTaskIds.remove(taskId)
                                    }
                                }
                            }
                            guard let onCompleteTask else { return nil }
                            return {
                                completingTaskIds.insert(taskId)
                                onCompleteTask(taskId)
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
                        } : nil
                    )
                }
            }
            .padding(.bottom, isLast ? 0 : ExecutiveTimelineVisuals.rowSpacing)
        }
    }

    @ViewBuilder
    private func interactiveBlock<Content: View>(
        for row: ExecutivePlanningTimelineRow,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if let taskID = row.taskId, !row.isCompleted, !isPreview {
            let resolved = constraintVM.constraintsByTaskID[taskID] ?? row.timeConstraint
            LifeBlockView(
                taskID: taskID,
                constraint: resolved,
                isEnabled: true,
                viewModel: constraintVM,
                scrollDisabled: $blockScrollDisabled
            ) {
                content()
            }
            .preference(key: TimelineBlockScrollDisabledKey.self, value: blockScrollDisabled)
            .overlay(alignment: .trailing) {
                constraintBadge(resolved)
                    .padding(.trailing, DesignSystem.spacingSM)
                    .padding(.top, DesignSystem.spacingSM)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        } else {
            content()
        }
    }

    private func constraintBadge(_ constraint: TimeConstraint) -> some View {
        Text(constraint.displayName)
            .font(.dsCaption(weight: .semibold))
            .foregroundColor(DesignSystem.textMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(DesignSystem.backgroundElevated.opacity(0.9)))
            .accessibilityHidden(true)
    }

    private func dotPhase(for row: ExecutivePlanningTimelineRow, uiPhase: TimelineEventPhase) -> TimelineEventPhase {
        if row.isCompleted { return .completed }
        if uiPhase == .passed { return .passed }
        if uiPhase == .current { return .current }
        return .upcoming
    }

    private func railSegmentColor(for row: ExecutivePlanningTimelineRow, phase: TimelineEventPhase) -> Color {
        switch phase {
        case .completed, .passed:
            return ExecutiveTimelineVisuals.lime.opacity(0.85)
        case .current:
            return ExecutiveTimelineVisuals.lime.opacity(0.45)
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

    private func progressLineEndY(phases: [TimelineEventPhase]) -> CGFloat {
        guard !isPreview else { return 0 }
        guard railHeight > 0, !rows.isEmpty else { return 0 }

        if let currentIndex = phases.firstIndex(of: .current),
           let center = dotCenters[rows[currentIndex].id] {
            return center
        }

        if let lastPassed = phases.lastIndex(where: { $0 == .completed || $0 == .passed }),
           let center = dotCenters[rows[lastPassed].id] {
            return center + ExecutiveTimelineVisuals.dotCompleted
        }

        return 0
    }
}

// MARK: - Continuous track (single line + progress)

private struct ContinuousTimelineTrack: View {
    let height: CGFloat
    let progressY: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            if height > 0 {
                // Muted full track — centered in gutter
                HStack {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: ExecutiveTimelineVisuals.lineWidth / 2, style: .continuous)
                        .fill(ExecutiveTimelineVisuals.trackMuted)
                        .frame(width: ExecutiveTimelineVisuals.lineWidth, height: height)
                    Spacer(minLength: 0)
                }

                // Fluorescent progress — grows downward
                if progressY > 0 {
                    HStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: ExecutiveTimelineVisuals.lineWidth / 2, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        ExecutiveTimelineVisuals.lime,
                                        ExecutiveTimelineVisuals.lime.opacity(0.85)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: ExecutiveTimelineVisuals.lineWidth, height: progressY)
                            .shadow(color: ExecutiveTimelineVisuals.lime.opacity(0.35), radius: 4, y: 0)
                        Spacer(minLength: 0)
                    }
                    .animation(.spring(response: 0.55, dampingFraction: 0.82), value: progressY)
                }
            }
        }
        .frame(width: ExecutiveTimelineVisuals.gutterWidth)
    }
}

// MARK: - Dot

private struct TimelineDotView: View {
    let phase: TimelineEventPhase

    var body: some View {
        ZStack {
            switch phase {
            case .completed:
                Circle()
                    .fill(ExecutiveTimelineVisuals.lime)
                    .frame(width: ExecutiveTimelineVisuals.dotCompleted + 2, height: ExecutiveTimelineVisuals.dotCompleted + 2)
                Image(systemName: "checkmark")
                    .font(.system(size: 6, weight: .black))
                    .foregroundColor(Color.black.opacity(0.85))

            case .passed:
                Circle()
                    .fill(ExecutiveTimelineVisuals.lime.opacity(0.55))
                    .frame(width: ExecutiveTimelineVisuals.dotCompleted, height: ExecutiveTimelineVisuals.dotCompleted)

            case .current:
                Circle()
                    .fill(ExecutiveTimelineVisuals.lime.opacity(0.25))
                    .frame(width: ExecutiveTimelineVisuals.dotCurrent + 10, height: ExecutiveTimelineVisuals.dotCurrent + 10)

                Circle()
                    .fill(ExecutiveTimelineVisuals.lime)
                    .frame(width: ExecutiveTimelineVisuals.dotCurrent, height: ExecutiveTimelineVisuals.dotCurrent)
                    .shadow(color: ExecutiveTimelineVisuals.lime.opacity(0.45), radius: 6)

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
    var isCompleting: Bool = false
    var isUncompleting: Bool = false
    var isRescheduling: Bool = false
    var isActionsExpanded: Bool = false
    var showsTaskActions: Bool = false
    var onToggleActions: (() -> Void)?
    var onStart: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDoubleTapComplete: (() -> Void)?
    var onReschedule: (() -> Void)?

    /// Auction-filled casualty — brief sparkle ("I found this time for you").
    private var isResurrectedSparkle: Bool {
        guard let id = row.taskId else { return false }
        return ResurrectedTaskRegistry.shared.isResurrected(id)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: DesignSystem.spacingSM) {
                categoryIcon

                Text(row.kind.sectionLabel.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(row.isCompleted ? DesignSystem.textMuted.opacity(0.7) : DesignSystem.textMuted)
                    .tracking(0.6)

                if row.isCompleted {
                    Text("DONE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(ExecutiveTimelineVisuals.lime)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(ExecutiveTimelineVisuals.lime.opacity(0.15)))
                } else if phase == .current {
                    Text("NOW")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(ExecutiveTimelineVisuals.lime)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(ExecutiveTimelineVisuals.lime.opacity(0.15)))
                } else if phase == .passed {
                    Text("Passed")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(ExecutiveTimelineVisuals.lime.opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(ExecutiveTimelineVisuals.lime.opacity(0.12)))
                } else if phase != .completed {
                    Text(row.scheduleRangeLabel.isEmpty ? row.timeLabel : row.scheduleRangeLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DesignSystem.textMuted)
                }

                Spacer(minLength: 0)

                if row.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ExecutiveTimelineVisuals.lime)
                } else if row.change != .unchanged {
                    deltaBadge(for: row.change)
                }
            }

            Text(row.title)
                .font(.dsBody())
                .fontWeight(phase == .current && !row.isCompleted ? .semibold : .regular)
                .foregroundColor(titleColor)
                .lineLimit(3)

            if showsTaskScheduleDetails {
                scheduleMetadata
            } else if !row.subtitle.isEmpty {
                Text(row.subtitle)
                    .font(.dsCaption())
                    .foregroundColor(row.isCompleted ? DesignSystem.textMuted : DesignSystem.textSecondary)
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
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(row.isPast ? "Reschedule to next open slot" : "Reschedule")
                            .font(.system(size: 12, weight: .semibold, design: .default))
                    }
                    .foregroundColor(ExecutiveTimelineVisuals.lime)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(ExecutiveTimelineVisuals.lime.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRescheduling)
                .padding(.top, 2)
            }

            if !row.detailLines.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(row.detailLines, id: \.self) { line in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(DesignSystem.textMuted.opacity(0.35))
                                .frame(width: 3, height: 3)
                            Text(line)
                                .font(.dsCaption())
                                .foregroundColor(DesignSystem.textSecondary)
                        }
                    }
                }
                .padding(.top, 2)
            }

            if isActionsExpanded, showsTaskActions {
                VStack(spacing: DesignSystem.spacingSM) {
                    if let onStart {
                        Button(action: onStart) {
                            Label("Start now", systemImage: "play.fill")
                                .font(.dsCaption(weight: .semibold))
                                .foregroundColor(DesignSystem.accentOnPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DesignSystem.spacingSM)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(DesignSystem.accentPrimary)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("focus-start-now")
                    }
                    if let onEdit {
                        Button(action: onEdit) {
                            Label("Edit task", systemImage: "pencil")
                                .font(.dsCaption(weight: .semibold))
                                .foregroundColor(DesignSystem.accentPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DesignSystem.spacingSM)
                                .background(
                                    Capsule(style: .continuous)
                                        .stroke(DesignSystem.accentPrimary, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, DesignSystem.spacingXS)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(DesignSystem.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous)
                .stroke(isActionsExpanded ? DesignSystem.accentPrimary.opacity(0.35) : borderColor, lineWidth: phase == .current || isActionsExpanded ? 1 : 0.5)
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
        .opacity(row.isCompleted ? 0.72 : ((isCompleting || isUncompleting || isRescheduling) ? 0.55 : 1))
        .scaleEffect((isCompleting || isUncompleting || isRescheduling) ? 0.98 : 1)
        .contentShape(RoundedRectangle(cornerRadius: DesignSystem.radiusMD, style: .continuous))
        .onTapGesture(count: 1) {
            if showsTaskActions {
                onToggleActions?()
            }
        }
        .onTapGesture(count: 2) {
            onDoubleTapComplete?()
        }
        .accessibilityIdentifier(row.taskId.map { "timeline-event-card-\($0)" } ?? "timeline-event-card")
        .accessibilityAction(named: row.isCompleted ? "Mark incomplete" : "Mark complete") {
            onDoubleTapComplete?()
        }
        .accessibilityHint(
            onDoubleTapComplete == nil
                ? ""
                : row.isCompleted
                    ? "Double tap to mark this task incomplete."
                    : "Double tap to mark this task complete."
        )
    }

    private var showsTaskScheduleDetails: Bool {
        row.taskId != nil || row.estimatedMinutes != nil || row.completedAt != nil
    }

    private var scheduleMetadata: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 14) {
                let rangeText = row.scheduleRangeLabel.isEmpty ? row.timeLabel : row.scheduleRangeLabel
                metadataItem(icon: "clock", text: "Scheduled \(rangeText)")
                if let minutes = row.estimatedMinutes, minutes > 0 {
                    metadataItem(icon: "hourglass", text: minutes.durationString)
                }
            }

            if row.isCompleted, let completedAt = row.completedAt {
                metadataItem(
                    icon: "checkmark.circle",
                    text: "Completed \(Self.timeFormatter.string(from: completedAt))"
                )
            }
        }
        .padding(.top, 2)
    }

    private func metadataItem(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .default))
        }
        .foregroundColor(row.isCompleted ? DesignSystem.textMuted : DesignSystem.textSecondary)
    }

    private var categoryIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(row.isCompleted ? ExecutiveTimelineVisuals.lime.opacity(0.2) : DesignSystem.backgroundElevated)
                .frame(width: 26, height: 26)
            Image(systemName: row.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(row.isCompleted ? ExecutiveTimelineVisuals.lime : DesignSystem.textSecondary)
                .symbolRenderingMode(.hierarchical)
        }
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
        if row.isConflict { return AnyShapeStyle(Color.orange.opacity(0.1)) }
        switch phase {
        case .current:
            return AnyShapeStyle(DesignSystem.backgroundElevated.opacity(0.95))
        case .completed, .passed:
            return AnyShapeStyle(DesignSystem.backgroundSecondary.opacity(0.35))
        case .upcoming:
            return AnyShapeStyle(DesignSystem.backgroundElevated.opacity(0.65))
        }
    }

    private var borderColor: Color {
        if row.isConflict { return Color.orange.opacity(0.4) }
        if phase == .current { return ExecutiveTimelineVisuals.lime.opacity(0.35) }
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
            case .conflict: return ("Conflict", .orange)
            case .unchanged: return ("", .clear)
            }
        }()
        if !label.isEmpty {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(color)
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
