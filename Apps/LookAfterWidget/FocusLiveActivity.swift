import ActivityKit
import WidgetKit
import SwiftUI
import LookAfterCore
#if canImport(AppIntents)
import AppIntents
#endif

/// Determinate progress bar for Live Activities — `ProgressView` renders as a stuck spinner in ActivityKit.
private struct LiveActivityLinearProgress: View {
    let fraction: Double
    let tint: Color
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(0.22))
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: height)
    }
}

private enum LiveActivityStyle {
    // Fixed opaque colors — adaptive tokens can resolve to zero-size layers in ActivityKit snapshots.
    static let accent = Color(hex: "5A9E3F")
    static let textPrimary = Color(hex: "F4F4F4")
    static let textSecondary = Color(hex: "B7BDC6")
    static let textMuted = Color(hex: "8D939C")
    static let background = Color(hex: "111315")

    static func accent(for mode: String, isOnBreak: Bool) -> Color {
        if isOnBreak { return textSecondary }
        switch mode {
        case "anchored": return accent
        case "recovery": return Color(red: 0.45, green: 0.72, blue: 0.62)
        case "fluidGap": return textMuted
        default: return accent
        }
    }
}

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            focusLockScreen(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: leadingIcon(context: context))
                        .foregroundColor(islandAccent(context: context))
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(context.state.sessionLabel)
                                .font(.dsMetadata())
                                .foregroundColor(LiveActivityStyle.textMuted)
                            Text(context.state.constraintType)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(LiveActivityStyle.textMuted.opacity(0.2))
                                .clipShape(Capsule())
                                .foregroundColor(LiveActivityStyle.textSecondary)
                        }
                        Text(context.state.taskTitle)
                            .font(.dsCaption(weight: .semibold))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    trailingTimer(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        LiveActivityLinearProgress(
                            fraction: context.state.progressFraction,
                            tint: islandAccent(context: context)
                        )
                        if !context.state.nextUpSummary.isEmpty {
                            Text(context.state.nextUpSummary)
                                .font(.dsMetadata())
                                .foregroundColor(LiveActivityStyle.textMuted)
                                .lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: leadingIcon(context: context))
                    .foregroundColor(islandAccent(context: context))
            } compactTrailing: {
                compactTrailing(context: context)
            } minimal: {
                Image(systemName: leadingIcon(context: context))
                    .foregroundColor(islandAccent(context: context))
            }
        }
    }

    private func leadingIcon(context: ActivityViewContext<FocusActivityAttributes>) -> String {
        if context.state.isOnBreak { return "cup.and.saucer.fill" }
        if context.state.surfaceModeRaw == "recovery" { return "figure.mind.and.body" }
        if context.state.surfaceModeRaw == "fluidGap" { return "hourglass" }
        return context.attributes.categoryIcon.isEmpty ? "brain.head.profile" : context.attributes.categoryIcon
    }

    private func islandAccent(context: ActivityViewContext<FocusActivityAttributes>) -> Color {
        LiveActivityStyle.accent(for: context.state.surfaceModeRaw, isOnBreak: context.state.isOnBreak)
    }

    private func endDate(for context: ActivityViewContext<FocusActivityAttributes>) -> Date {
        max(Date().addingTimeInterval(1), context.state.sessionEndDate)
    }

    @ViewBuilder
    private func trailingTimer(context: ActivityViewContext<FocusActivityAttributes>) -> some View {
        if context.state.isPaused || !context.state.showsStrictCountdown {
            Text(context.state.remainingLabel.isEmpty ? "—" : context.state.remainingLabel)
                .font(.dsCaption(weight: .semibold).monospacedDigit())
                .foregroundColor(islandAccent(context: context))
        } else {
            Text(timerInterval: Date()...endDate(for: context), countsDown: true)
                .font(.dsCaption(weight: .semibold).monospacedDigit())
                .multilineTextAlignment(.trailing)
                .foregroundColor(islandAccent(context: context))
        }
    }

    @ViewBuilder
    private func compactTrailing(context: ActivityViewContext<FocusActivityAttributes>) -> some View {
        if context.state.isPaused || !context.state.showsStrictCountdown {
            Text(context.state.remainingLabel.isEmpty ? "·" : context.state.remainingLabel)
                .font(.dsMetadata().monospacedDigit())
                .foregroundColor(islandAccent(context: context))
        } else {
            Text(timerInterval: Date()...endDate(for: context), countsDown: true)
                .font(.dsMetadata().monospacedDigit())
                .frame(width: 40)
                .foregroundColor(islandAccent(context: context))
        }
    }

    @ViewBuilder
    private func focusLockScreen(context: ActivityViewContext<FocusActivityAttributes>) -> some View {
        let accent = islandAccent(context: context)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(context.state.sessionLabel, systemImage: leadingIcon(context: context))
                    .font(.dsMetadata(weight: .bold))
                    .foregroundColor(accent)
                Spacer()
                Text(context.state.constraintType)
                    .font(.dsMetadata(weight: .semibold))
                    .foregroundColor(LiveActivityStyle.textMuted)
            }

            Text(context.state.taskTitle)
                .font(.dsHeadline())
                .foregroundColor(LiveActivityStyle.textPrimary)
                .lineLimit(2)

            HStack(alignment: .firstTextBaseline) {
                if context.state.isPaused {
                    Text("Paused • \(context.state.remainingLabel)")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(accent)
                } else if context.state.showsStrictCountdown {
                    Text(timerInterval: Date()...endDate(for: context), countsDown: true)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(accent)
                } else {
                    Text(context.state.remainingLabel.isEmpty ? context.state.constraintType : context.state.remainingLabel)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(accent)
                }
                Spacer()
                Text("\(Int(context.state.progressFraction * 100))%")
                    .font(.dsCaption(weight: .semibold).monospacedDigit())
                    .foregroundColor(LiveActivityStyle.textMuted)
            }

            LiveActivityLinearProgress(fraction: context.state.progressFraction, tint: accent)

            if !context.state.nextUpSummary.isEmpty {
                Text(context.state.nextUpSummary)
                    .font(.dsMetadata())
                    .foregroundColor(LiveActivityStyle.textSecondary)
                    .lineLimit(2)
            }

            focusControlButtons
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .activityBackgroundTint(LiveActivityStyle.background)
    }

    @ViewBuilder
    private var focusControlButtons: some View {
        if #available(iOS 17.0, *) {
            HStack(spacing: 12) {
                Button(intent: WidgetPauseFocusIntent()) {
                    Label("Rest", systemImage: "pause.circle.fill")
                        .font(.dsCaption(weight: .semibold))
                }
                .buttonStyle(.bordered)
                .tint(LiveActivityStyle.textSecondary)

                Button(intent: WidgetCompleteFocusIntent()) {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.dsCaption(weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(LiveActivityStyle.accent)
            }
            .padding(.top, 4)
        }
    }
}

struct NowPinLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPinActivityAttributes.self) { context in
            nowLockScreen(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: pinIcon(context))
                        .font(.body.weight(.semibold))
                        .foregroundColor(LiveActivityStyle.accent)
                        .frame(width: 24, height: 24)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.sectionLabel.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(LiveActivityStyle.textMuted)
                        Text(nowPinTitle(context))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .foregroundColor(LiveActivityStyle.textPrimary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(max(0, context.state.energyScore))%")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundColor(LiveActivityStyle.accent)
                        Text(energyLabel(context))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(LiveActivityStyle.textMuted)
                    }
                    .frame(minWidth: 28, minHeight: 28)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if context.state.progressFraction > 0 {
                            LiveActivityLinearProgress(
                                fraction: context.state.progressFraction,
                                tint: LiveActivityStyle.accent
                            )
                        }
                        Text(nowPinBottomLine(context))
                            .font(.caption2)
                            .lineLimit(2)
                            .foregroundColor(LiveActivityStyle.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 14, alignment: .leading)
                    }
                }
            } compactLeading: {
                Image(systemName: pinIcon(context))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(LiveActivityStyle.accent)
                    .frame(width: 18, height: 18)
            } compactTrailing: {
                Text("\(max(0, context.state.energyScore))%")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundColor(LiveActivityStyle.accent)
                    .frame(minWidth: 24, minHeight: 16)
            } minimal: {
                Image(systemName: pinIcon(context))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(LiveActivityStyle.accent)
                    .frame(width: 16, height: 16)
            }
        }
    }

    private func pinIcon(_ context: ActivityViewContext<NowPinActivityAttributes>) -> String {
        let stateIcon = context.state.categoryIcon.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stateIcon.isEmpty { return stateIcon }
        let icon = context.attributes.categoryIcon.trimmingCharacters(in: .whitespacesAndNewlines)
        return icon.isEmpty ? "sparkles" : icon
    }

    private func nowPinTitle(_ context: ActivityViewContext<NowPinActivityAttributes>) -> String {
        let title = context.state.topTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Next step" : title
    }

    private func nowPinContextLine(_ context: ActivityViewContext<NowPinActivityAttributes>) -> String {
        let sanitized = UserFacingCopy.sanitize(context.state.contextLine)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized
    }

    private func nowPinBottomLine(_ context: ActivityViewContext<NowPinActivityAttributes>) -> String {
        let schedule = context.state.scheduleLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let contextLine = nowPinContextLine(context)
        if !schedule.isEmpty, !contextLine.isEmpty {
            return "\(schedule) · \(contextLine)"
        }
        if !schedule.isEmpty { return schedule }
        if !contextLine.isEmpty { return contextLine }
        let minutes = max(1, context.state.estimatedMinutes)
        return "~\(minutes) min • \(energyLabel(context)) energy"
    }

    @ViewBuilder
    private func nowLockScreen(context: ActivityViewContext<NowPinActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: pinIcon(context))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(LiveActivityStyle.accent)
                    .frame(width: 16, height: 16)

                Text(context.state.sectionLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundColor(LiveActivityStyle.accent)
                    .lineLimit(1)
                    .frame(minHeight: 14)

                if !context.state.constraintLabel.isEmpty {
                    Text(context.state.constraintLabel)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(LiveActivityStyle.textMuted.opacity(0.2))
                        .clipShape(Capsule())
                        .foregroundColor(LiveActivityStyle.textSecondary)
                }

                Text("\(max(0, context.state.energyScore))%")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundColor(LiveActivityStyle.textMuted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .frame(minHeight: 14)
            }

            Text(nowPinTitle(context))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(LiveActivityStyle.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(context.state.scheduleLabel.isEmpty ? pinDurationLabel(context) : context.state.scheduleLabel)
                    .font(.caption)
                    .foregroundColor(LiveActivityStyle.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 14)

                if !context.state.scheduleLabel.isEmpty {
                    pinRemainingLabel(context)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundColor(LiveActivityStyle.accent)
                        .lineLimit(1)
                        .frame(minHeight: 14)
                }
            }

            pinProgressSection(context)

            if let footer = pinFooterLine(context) {
                Text(footer)
                    .font(.caption2)
                    .foregroundColor(LiveActivityStyle.textMuted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .activityBackgroundTint(LiveActivityStyle.background)
    }

    private func pinFooterLine(_ context: ActivityViewContext<NowPinActivityAttributes>) -> String? {
        let nextUp = context.state.nextUpSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nextUp.isEmpty { return nextUp }

        let contextLine = nowPinContextLine(context)
        if contextLine.isEmpty { return nil }
        if contextLine == "Ready when you are." { return nil }
        if contextLine == "Fixed window — stay in this block." { return nil }
        return contextLine
    }

    @ViewBuilder
    private func pinProgressSection(_ context: ActivityViewContext<NowPinActivityAttributes>) -> some View {
        if let start = context.state.windowStart,
           let end = context.state.windowEnd,
           end > start {
            TimelineView(.periodic(from: start, by: 30)) { timeline in
                let now = timeline.date
                let fraction = min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start)))
                LiveActivityLinearProgress(fraction: fraction, tint: LiveActivityStyle.accent)
            }
        } else if context.state.progressFraction > 0 {
            LiveActivityLinearProgress(fraction: context.state.progressFraction, tint: LiveActivityStyle.accent)
        }
    }

    @ViewBuilder
    private func pinRemainingLabel(_ context: ActivityViewContext<NowPinActivityAttributes>) -> some View {
        if let end = context.state.windowEnd {
            if end <= Date() {
                Text("Ended")
            } else if context.state.constraintLabel == "Anchored" {
                Text(timerInterval: Date()...max(Date().addingTimeInterval(1), end), countsDown: true)
            } else {
                Text(pinDurationLabel(context))
            }
        } else {
            Text(pinDurationLabel(context))
        }
    }

    private func pinDurationLabel(_ context: ActivityViewContext<NowPinActivityAttributes>) -> String {
        let minutes = max(1, context.state.estimatedMinutes)
        let formatted = PinNowSnapshotBuilder.compactDuration(minutes: minutes)
        if context.state.constraintLabel == "Anchored" {
            return "\(formatted) left"
        }
        return "~\(formatted)"
    }

    private func energyLabel(_ context: ActivityViewContext<NowPinActivityAttributes>) -> String {
        let level = context.state.energyLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        return level.isEmpty ? "Energy" : level
    }
}
