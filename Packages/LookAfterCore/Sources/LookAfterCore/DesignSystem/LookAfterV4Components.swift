import SwiftUI

// MARK: - Conversation card (Brain / Coach — no chat bubbles)

public struct LAConversationCard: View {
    let title: String?
    let bodyText: String
    var footnote: String?
    var isUser: Bool

    public init(
        title: String? = nil,
        bodyText: String,
        footnote: String? = nil,
        isUser: Bool = false
    ) {
        self.title = title
        self.bodyText = bodyText
        self.footnote = footnote
        self.isUser = isUser
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.dsCaption(weight: .semibold))
                    .foregroundColor(DesignSystem.textMuted)
                    .textCase(.uppercase)
                    .tracking(0.4)
            }

            Text(bodyText)
                .font(.dsBody())
                .foregroundColor(DesignSystem.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let footnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.dsMetadata())
                    .foregroundColor(DesignSystem.textMuted)
            }
        }
        .padding(DesignSystem.cardPaddingMin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                .fill(isUser ? DesignSystem.accentPrimary.opacity(0.12) : DesignSystem.backgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.radiusLG, style: .continuous)
                .stroke(DesignSystem.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isUser ? .isStaticText : .isSummaryElement)
    }
}

// MARK: - Timeline row (Apple Calendar aesthetic)

public struct LATimelineRow: View {
    let timeLabel: String
    let title: String
    var subtitle: String?
    var icon: String?
    var isCurrent: Bool
    var isCompleted: Bool
    var showsStrikethrough: Bool

    public init(
        timeLabel: String,
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        isCurrent: Bool = false,
        isCompleted: Bool = false,
        showsStrikethrough: Bool = true
    ) {
        self.timeLabel = timeLabel
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.isCurrent = isCurrent
        self.isCompleted = isCompleted
        self.showsStrikethrough = showsStrikethrough
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.spacingMD) {
            Text(timeLabel)
                .font(.dsMetadata(weight: .semibold))
                .foregroundColor(isCurrent ? DesignSystem.accentPrimary : DesignSystem.textMuted)
                .frame(width: 56, alignment: .trailing)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: DesignSystem.spacingXS) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.dsCaption(weight: .semibold))
                            .foregroundColor(DesignSystem.textSecondary)
                    }
                    Group {
                        if showsStrikethrough && isCompleted {
                            Text(title)
                                .font(.dsBody(weight: isCurrent ? .semibold : .regular))
                                .foregroundColor(DesignSystem.textMuted)
                                .strikethrough(true)
                                .lineLimit(2)
                        } else {
                            Text(title)
                                .font(.dsBody(weight: isCurrent ? .semibold : .regular))
                                .foregroundColor(isCompleted ? DesignSystem.textMuted : DesignSystem.textPrimary)
                                .lineLimit(2)
                        }
                    }
                }

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, DesignSystem.spacingSM)
            .padding(.horizontal, DesignSystem.spacingMD)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous)
                    .fill(isCurrent ? DesignSystem.accentPrimary.opacity(0.08) : DesignSystem.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous)
                    .stroke(isCurrent ? DesignSystem.accentPrimary.opacity(0.25) : DesignSystem.divider, lineWidth: 1)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(timeLabel), \(title)")
        .accessibilityAddTraits(isCompleted ? .isStaticText : [])
    }
}

// MARK: - Bottom sheet scaffold

public struct LABottomSheet<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    public init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(DesignSystem.divider)
                .frame(width: 36, height: 4)
                .padding(.top, DesignSystem.spacingSM)
                .padding(.bottom, DesignSystem.spacingMD)
                .accessibilityHidden(true)

            if let title {
                Text(title)
                    .font(.dsHeadline())
                    .foregroundColor(DesignSystem.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DesignSystem.screenHorizontal)
                    .padding(.bottom, DesignSystem.spacingMD)
            }

            content
        }
        .background(DesignSystem.backgroundPrimary)
    }
}

// MARK: - V4 screen components (Phase 1)

private enum LAContentSurface {
    static func cardBackground() -> some View {
        RoundedRectangle(cornerRadius: LookAfterTypography.radiusCard, style: .continuous)
            .fill(DesignSystem.contentSurface)
            .shadow(
                color: DesignSystem.shadowElevated,
                radius: DesignSystem.shadowRadius,
                x: 0,
                y: DesignSystem.shadowYOffset
            )
    }

    static func cardBorder() -> some View {
        RoundedRectangle(cornerRadius: LookAfterTypography.radiusCard, style: .continuous)
            .stroke(DesignSystem.border, lineWidth: 1)
    }
}

// MARK: Category chip

public struct LACategoryChip: View {
    let title: String
    var color: Color

    public init(_ title: String, color: Color = DesignSystem.textSecondary) {
        self.title = title
        self.color = color
    }

    public var body: some View {
        Text(title)
            .textStyleCaption(color: DesignSystem.textPrimary)
            .dsChipText()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, DesignSystem.spacingSM)
            .padding(.vertical, DesignSystem.spacingXXS)
            .background(
                Capsule(style: .continuous)
                    .fill(DesignSystem.backgroundElevated)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(color.opacity(0.35), lineWidth: 1)
            )
            .accessibilityLabel(title)
    }
}

// MARK: Progress bar

public struct LAProgressBar: View {
    let label: String
    let progress: Double
    var showsPercentage: Bool
    var barHeight: CGFloat

    public init(
        label: String,
        progress: Double,
        showsPercentage: Bool = true,
        barHeight: CGFloat = 8
    ) {
        self.label = label
        self.progress = min(max(progress, 0), 1)
        self.showsPercentage = showsPercentage
        self.barHeight = barHeight
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
            HStack {
                Text(label)
                    .textStyleCaption(color: DesignSystem.textPrimary)
                Spacer()
                if showsPercentage {
                    Text("\(Int(progress * 100))%")
                        .font(.dsCaption(weight: .semibold))
                        .foregroundColor(DesignSystem.textPrimary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DesignSystem.backgroundElevated)
                    Capsule()
                        .fill(DesignSystem.accentPrimary)
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: barHeight)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(Int(progress * 100)) percent")
    }
}

// MARK: Progress ring

public struct LAProgressRing: View {
    let progress: Double
    var diameter: CGFloat
    var lineWidth: CGFloat

    public init(progress: Double, diameter: CGFloat = 32, lineWidth: CGFloat = 3) {
        self.progress = min(max(progress, 0), 1)
        self.diameter = diameter
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(DesignSystem.backgroundElevated, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(DesignSystem.accentPrimary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel("Progress \(Int(progress * 100)) percent")
    }
}

// MARK: Dismiss FAB

public struct LADismissFAB: View {
    let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: LAChromeMetrics.iconPointSize, weight: .bold))
                .foregroundStyle(DesignSystem.textPrimary)
                .frame(width: LAChromeMetrics.fabDiameter, height: LAChromeMetrics.fabDiameter)
                .background {
                    Circle()
                        .fill(DesignSystem.contentSurfaceElevated)
                        .overlay(
                            Circle()
                                .stroke(DesignSystem.border, lineWidth: 1)
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("capture-dismiss-fab")
        .accessibilityLabel("Close")
    }
}

// MARK: Executive Briefing card

public struct LAExecutiveBriefingCard: View {
    let summaryLines: [String]
    let buttonTitle: String
    var isLoading: Bool
    let onContinue: () -> Void

    public init(
        summaryLines: [String],
        buttonTitle: String = "See the rest →",
        isLoading: Bool = false,
        onContinue: @escaping () -> Void
    ) {
        self.summaryLines = summaryLines
        self.buttonTitle = buttonTitle
        self.isLoading = isLoading
        self.onContinue = onContinue
    }

    public init(summary: String, buttonTitle: String = "See the rest →", onContinue: @escaping () -> Void) {
        self.summaryLines = summary.isEmpty ? [] : [summary]
        self.buttonTitle = buttonTitle
        self.isLoading = false
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingMD) {
            Text("For today")
                .textStyleSectionLabel(color: DesignSystem.textSecondary)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)

            if isLoading, summaryLines.isEmpty {
                HStack(spacing: DesignSystem.spacingSM) {
                    ProgressView()
                        .scaleEffect(0.85)
                    Text("Summarizing your day…")
                        .textStyleBody(color: DesignSystem.textSecondary)
                }
            } else {
                VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
                    ForEach(Array(displayLines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: DesignSystem.spacingSM) {
                            Text("•")
                                .font(.dsBody(weight: .semibold))
                                .foregroundColor(DesignSystem.textSecondary)
                                .padding(.top, 1)

                            Text(line)
                                .textStyleBody()
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            Button(action: onContinue) {
                Text(buttonTitle)
                    .font(.dsBody(weight: .semibold))
                    .foregroundStyle(DesignSystem.accentOnPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DesignSystem.minTouchTarget)
            }
            .buttonStyle(.glassProminent)
            .tint(LookAfterChrome.accentTint)
            .accessibilityIdentifier("briefing-continue-cta")
        }
        .padding(DesignSystem.cardPaddingMin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LAContentSurface.cardBackground())
        .overlay(LAContentSurface.cardBorder())
        .accessibilityElement(children: .contain)
    }

    private var displayLines: [String] {
        if summaryLines.isEmpty {
            return ["Nothing pressing yet. Add a task or jot down a thought."]
        }
        return summaryLines
    }
}

// MARK: Briefing glance row

public struct LABriefingGlanceRow: View {
    let title: String
    let timeRange: String
    var dotColor: Color
    var showsRailAbove: Bool
    var showsRailBelow: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(
        title: String,
        timeRange: String,
        dotColor: Color = DesignSystem.focus,
        showsRailAbove: Bool = false,
        showsRailBelow: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.timeRange = timeRange
        self.dotColor = dotColor
        self.showsRailAbove = showsRailAbove
        self.showsRailBelow = showsRailBelow
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: DesignSystem.spacingMD) {
                ZStack {
                    GeometryReader { geo in
                        let midY = geo.size.height / 2
                        ZStack {
                            if showsRailAbove {
                                Rectangle()
                                    .fill(dotColor.opacity(0.35))
                                    .frame(width: 2, height: midY)
                                    .position(x: geo.size.width / 2, y: midY / 2)
                            }
                            if showsRailBelow {
                                Rectangle()
                                    .fill(dotColor.opacity(0.35))
                                    .frame(width: 2, height: midY)
                                    .position(x: geo.size.width / 2, y: midY + midY / 2)
                            }
                        }
                    }
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                }
                .frame(width: 12)
                .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 2) {
                    Text(TaskTitleDisplay.humanized(title))
                        .textStyleCardTitle()
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .truncationMode(.tail)
                    Text(timeRange)
                        .textStyleCaption()
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DesignSystem.textMuted)
                    .frame(width: DesignSystem.minTouchTarget, height: DesignSystem.minTouchTarget)
                    .contentShape(Rectangle())
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DesignSystem.spacingSM)
            .padding(.vertical, DesignSystem.spacingSM)
            .frame(maxWidth: .infinity, minHeight: DesignSystem.minTouchTarget, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(TaskTitleDisplay.humanized(title)), \(timeRange)")
    }
}

// MARK: Week date strip

public struct LAWeekDateStrip: View {
    let days: [Date]
    @Binding var selectedDate: Date
    var calendar: Calendar

    public init(days: [Date], selectedDate: Binding<Date>, calendar: Calendar = .current) {
        self.days = days
        self._selectedDate = selectedDate
        self.calendar = calendar
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f
    }()

    public var body: some View {
        HStack(spacing: DesignSystem.spacingXS) {
            ForEach(days, id: \.self) { day in
                let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
                Button(action: {
                    selectedDate = day
                }, label: {
                    VStack(spacing: 4) {
                        Text(Self.weekdayFormatter.string(from: day))
                            .textStyleCaption(color: isSelected ? DesignSystem.textPrimary : DesignSystem.textSecondary)
                        Text("\(calendar.component(.day, from: day))")
                            .font(.dsCaption(weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? DesignSystem.textPrimary : DesignSystem.textPrimary.opacity(0.85))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.spacingXS)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous)
                            .fill(isSelected ? DesignSystem.backgroundElevated : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous)
                            .stroke(isSelected ? DesignSystem.border : Color.clear, lineWidth: 1)
                    )
                })
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("today-week-strip")
    }
}

// MARK: Priority row

public struct LAPriorityRow: View {
    let title: String
    let category: String
    var detail: String?
    var ringColor: Color
    var isComplete: Bool
    var isActionsExpanded: Bool = false
    let onToggle: () -> Void
    let onToggleActions: () -> Void
    var onStart: (() -> Void)?
    var onEdit: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    public init(
        title: String,
        category: String,
        detail: String? = nil,
        ringColor: Color = DesignSystem.textSecondary,
        isComplete: Bool = false,
        isActionsExpanded: Bool = false,
        onToggle: @escaping () -> Void,
        onToggleActions: @escaping () -> Void,
        onStart: (() -> Void)? = nil,
        onEdit: (() -> Void)? = nil
    ) {
        self.title = title
        self.category = category
        self.detail = detail
        self.ringColor = ringColor
        self.isComplete = isComplete
        self.isActionsExpanded = isActionsExpanded
        self.onToggle = onToggle
        self.onToggleActions = onToggleActions
        self.onStart = onStart
        self.onEdit = onEdit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSM) {
            HStack(spacing: DesignSystem.spacingSM) {
                Circle()
                    .stroke(ringColor, lineWidth: 2)
                    .frame(width: 22, height: 22)
                    .overlay {
                        if isComplete {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(ringColor)
                        }
                    }
                    .onTapGesture(count: 2, perform: onToggle)
                    .accessibilityLabel(isComplete ? "Mark incomplete" : "Mark complete")
                    .accessibilityHint("Double tap to toggle completion")

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.dsBody(weight: .semibold))
                        .lineLimit(2)
                        .strikethrough(isComplete)
                        .foregroundColor(isComplete ? DesignSystem.textMuted : DesignSystem.textPrimary)

                    HStack(spacing: DesignSystem.spacingXS) {
                        LACategoryChip(category, color: ringColor)
                            .layoutPriority(1)
                        if let detail, !detail.isEmpty {
                            Text(detail)
                                .font(.dsTabLabel())
                                .foregroundColor(DesignSystem.textMuted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .truncationMode(.middle)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Image(systemName: isActionsExpanded ? "chevron.up" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DesignSystem.textMuted)
            }

            if isActionsExpanded, !isComplete {
                VStack(spacing: DesignSystem.spacingSM) {
                    if let onStart {
                        Button(action: onStart) {
                            Label("Start now", systemImage: "play.fill")
                                .font(.dsCaption(weight: .semibold))
                                .foregroundColor(DesignSystem.accentOnPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DesignSystem.spacingSM)
                                .background(Capsule(style: .continuous).fill(DesignSystem.accentPrimary))
                        }
                        .buttonStyle(.plain)
                    }
                    if let onEdit {
                        Button(action: onEdit) {
                            Label("Edit task", systemImage: "pencil")
                                .font(.dsCaption(weight: .semibold))
                                .foregroundColor(DesignSystem.accentPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DesignSystem.spacingSM)
                                .background(Capsule(style: .continuous).stroke(DesignSystem.accentPrimary, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, DesignSystem.spacingXS)
        .padding(.vertical, DesignSystem.spacingSM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            if !isActionsExpanded {
                Divider().opacity(0.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleActions)
        .animation(.easeInOut(duration: 0.22), value: isActionsExpanded)
        .accessibilityIdentifier("priority-row-\(title.prefix(20))")
    }
}

// MARK: Schedule row

public struct LAScheduleRow: View {
    let timeLabel: String
    let title: String
    let durationLabel: String
    let action: () -> Void

    public init(timeLabel: String, title: String, durationLabel: String, action: @escaping () -> Void) {
        self.timeLabel = timeLabel
        self.title = title
        self.durationLabel = durationLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: DesignSystem.spacingXS) {
                    Text(timeLabel)
                        .textStyleCaption(color: DesignSystem.textPrimary)
                    Text("·")
                        .textStyleCaption()
                    Text(title)
                        .textStyleCardTitle()
                }
                Text(durationLabel)
                    .textStyleCaption()
            }
            .padding(DesignSystem.spacingMD)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: LookAfterTypography.radiusCard, style: .continuous)
                    .fill(DesignSystem.backgroundSecondary)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: Capture type row

public struct LACaptureTypeRow: View {
    let title: String
    let subtitle: String
    let icon: String
    var iconColor: Color
    let action: () -> Void

    public init(title: String, subtitle: String, icon: String, iconColor: Color, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColor = iconColor
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.spacingMD) {
                Image(systemName: icon)
                    .font(.dsIcon())
                    .foregroundColor(iconColor)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.radiusSM, style: .continuous)
                            .fill(iconColor.opacity(0.12))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .textStyleCardTitle()
                    Text(subtitle)
                        .textStyleCaption()
                }
                Spacer(minLength: 0)
            }
            .padding(DesignSystem.spacingMD)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: LookAfterTypography.radiusCard, style: .continuous)
                    .fill(DesignSystem.backgroundSecondary)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("capture-type-\(title.lowercased())")
    }
}

// MARK: Brain voice orb

public enum LABrainVoiceOrbState: String, CaseIterable {
    case ready
    case listening
    case thinking
    case speaking
}

public struct LABrainVoiceOrb: View {
    let state: LABrainVoiceOrbState
    var diameter: CGFloat
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false
    @State private var ripple = false

    public init(state: LABrainVoiceOrbState, diameter: CGFloat = 200, onTap: @escaping () -> Void) {
        self.state = state
        self.diameter = diameter
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            ZStack {
                // Soft outer glow — restrained
                Circle()
                    .fill(orbAccent.opacity(0.12))
                    .frame(width: diameter * 1.12, height: diameter * 1.12)
                    .blur(radius: reduceMotion ? 6 : 12)

                if state == .listening && !reduceMotion {
                    Circle()
                        .stroke(orbAccent.opacity(0.45), lineWidth: 2)
                        .frame(
                            width: diameter * (ripple ? 1.12 : 1.02),
                            height: diameter * (ripple ? 1.12 : 1.02)
                        )
                        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: ripple)
                }

                // Core filled orb
                Circle()
                    .fill(
                        RadialGradient(
                            colors: orbColors,
                            center: UnitPoint(x: 0.35, y: 0.32),
                            startRadius: 0,
                            endRadius: diameter * 0.62
                        )
                    )
                    .frame(width: diameter * breatheScale, height: diameter * breatheScale)
                    .overlay {
                        // Specular highlight — depth so it doesn’t read as a flat blob
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.white.opacity(0.55),
                                        Color.white.opacity(0.08),
                                        Color.clear
                                    ],
                                    center: UnitPoint(x: 0.32, y: 0.28),
                                    startRadius: 0,
                                    endRadius: diameter * 0.42
                                )
                            )
                            .blendMode(.softLight)
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.55),
                                        orbAccent.opacity(0.35),
                                        Color.black.opacity(0.12)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
                    .shadow(color: orbAccent.opacity(0.35), radius: state == .thinking ? 28 : 18, x: 0, y: 10)

                if state == .thinking {
                    ProgressView()
                        .tint(DesignSystem.textPrimary.opacity(0.7))
                        .scaleEffect(1.1)
                }
            }
            .frame(width: diameter * 1.2, height: diameter * 1.2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("brain-voice-orb")
        .accessibilityLabel(accessibilityLabel)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                breathe = true
            }
            ripple = true
        }
    }

    private var breatheScale: CGFloat {
        guard !reduceMotion, state == .ready || state == .speaking else { return 1.0 }
        return breathe ? 1.03 : 0.97
    }

    private var orbAccent: Color {
        switch state {
        case .ready: return DesignSystem.accentPrimary
        case .listening: return DesignSystem.accentPrimary
        case .thinking: return DesignSystem.textSecondary
        case .speaking: return DesignSystem.accentPrimary
        }
    }

    private var orbColors: [Color] {
        // Lime / neutral family — same brand as the rest of the app (no purple split).
        switch state {
        case .ready:
            return [
                DesignSystem.contentSurfaceElevated,
                DesignSystem.accentPrimary.opacity(0.35),
                DesignSystem.accentPrimary.opacity(0.55)
            ]
        case .listening:
            return [
                Color(hex: "E8FFD4"),
                DesignSystem.accentPrimary.opacity(0.65),
                DesignSystem.accentPrimary
            ]
        case .thinking:
            return [
                DesignSystem.contentSurface,
                DesignSystem.textMuted.opacity(0.35),
                DesignSystem.textSecondary.opacity(0.55)
            ]
        case .speaking:
            return [
                Color(hex: "F0F7E8"),
                DesignSystem.accentPrimary.opacity(0.45),
                DesignSystem.accentPrimary.opacity(0.7)
            ]
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .ready: return "Voice orb ready. Tap to speak."
        case .listening: return "Listening"
        case .thinking: return "Thinking"
        case .speaking: return "Speaking"
        }
    }
}

// MARK: - Section card (Briefing / Today)

public struct LASectionCard<Content: View>: View {
    let title: String
    var subtitle: String?
    var icon: String?
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme

    public init(title: String, subtitle: String? = nil, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.content = content()
    }

    public var body: some View {
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
            }

            content
        }
        .padding(DesignSystem.cardPaddingMin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LookAfterTypography.radiusCard, style: .continuous)
                .fill(DesignSystem.backgroundSecondary)
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
        )
        .overlay(
            RoundedRectangle(cornerRadius: LookAfterTypography.radiusCard, style: .continuous)
                .stroke(DesignSystem.border, lineWidth: 1)
        )
    }
}

// MARK: - Analog focus clock (ADHD session timer)

public struct AnalogFocusClockView: View {
    let progress: Double
    var accentColor: Color = DesignSystem.accentPrimary
    var trackColor: Color = DesignSystem.border
    var size: CGFloat = 220

    public init(progress: Double, accentColor: Color = DesignSystem.accentPrimary, trackColor: Color = DesignSystem.border, size: CGFloat = 220) {
        self.progress = progress
        self.accentColor = accentColor
        self.trackColor = trackColor
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: 6)
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    accentColor,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .frame(width: size - 8, height: size - 8)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)

            elapsedWedge

            clockTicks

            sessionHand
        }
        .accessibilityHidden(true)
    }

    private var elapsedWedge: some View {
        Circle()
            .trim(from: 0, to: min(max(progress, 0), 1))
            .fill(accentColor.opacity(0.14))
            .frame(width: size - 28, height: size - 28)
            .rotationEffect(.degrees(-90))
            .animation(.linear(duration: 1), value: progress)
    }

    private var clockTicks: some View {
        ForEach(0..<12, id: \.self) { tick in
            Rectangle()
                .fill(DesignSystem.textMuted.opacity(0.35))
                .frame(width: 1.5, height: tick % 3 == 0 ? 10 : 6)
                .offset(y: -(size / 2) + 14)
                .rotationEffect(.degrees(Double(tick) * 30))
        }
    }

    private var sessionHand: some View {
        Capsule(style: .continuous)
            .fill(accentColor)
            .frame(width: 3, height: size * 0.32)
            .offset(y: -(size * 0.16))
            .rotationEffect(.degrees(progress * 360 - 90))
            .animation(.linear(duration: 1), value: progress)
    }
}
