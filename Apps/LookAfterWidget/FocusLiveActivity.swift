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
                    .fill(LiveActivityStyle.trackPlate)
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
    // Dark plate tuned for glass Lock Screen / Dynamic Island contrast (V5 brand green accent).
    static let accent = Color(hex: "5A9E3F")
    static let textPrimary = Color(hex: "F5F6F4")
    static let textSecondary = Color(hex: "C2C7CE")
    static let textMuted = Color(hex: "949AA3")
    static let background = Color(hex: "0E1012")
    /// Opaque secondary plate for constraint chips / progress tracks (no white.opacity wash).
    static let chipPlate = Color(hex: "23282E")
    static let trackPlate = Color(hex: "1A1E22")

    static func accent(for mode: String, isOnBreak: Bool) -> Color {
        if isOnBreak { return textSecondary }
        switch mode {
        case "anchored": return accent
        case "recovery": return Color(hex: "74C69D")
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
                        .foregroundStyle(islandAccent(context: context))
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(context.state.sessionLabel)
                                .font(.dsMetadata())
                                .foregroundStyle(LiveActivityStyle.textMuted)
                            Text(context.state.constraintType)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(LiveActivityStyle.chipPlate))
                                .foregroundStyle(LiveActivityStyle.textSecondary)
                        }
                        Text(context.state.taskTitle)
                            .font(.dsCaption(weight: .semibold))
                            .foregroundStyle(LiveActivityStyle.textPrimary)
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
                                .foregroundStyle(LiveActivityStyle.textMuted)
                                .lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: leadingIcon(context: context))
                    .foregroundStyle(islandAccent(context: context))
            } compactTrailing: {
                compactTrailing(context: context)
            } minimal: {
                Image(systemName: leadingIcon(context: context))
                    .foregroundStyle(islandAccent(context: context))
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
            Text(context.state.remainingLabel.isEmpty ? "—" : Self.upgradedDurationLabel(context.state.remainingLabel))
                .font(.dsCaption(weight: .semibold).monospacedDigit())
                .foregroundStyle(islandAccent(context: context))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            Text(timerInterval: Date()...endDate(for: context), countsDown: true)
                .font(.dsCaption(weight: .semibold).monospacedDigit())
                .multilineTextAlignment(.trailing)
                .foregroundStyle(islandAccent(context: context))
        }
    }

    @ViewBuilder
    private func compactTrailing(context: ActivityViewContext<FocusActivityAttributes>) -> some View {
        if context.state.isPaused || !context.state.showsStrictCountdown {
            Text(context.state.remainingLabel.isEmpty ? "·" : Self.upgradedDurationLabel(context.state.remainingLabel))
                .font(.dsMetadata().monospacedDigit())
                .foregroundStyle(islandAccent(context: context))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            Text(timerInterval: Date()...endDate(for: context), countsDown: true)
                .font(.dsMetadata().monospacedDigit())
                .frame(width: 40)
                .foregroundStyle(islandAccent(context: context))
        }
    }

    @ViewBuilder
    private func focusLockScreen(context: ActivityViewContext<FocusActivityAttributes>) -> some View {
        let accent = islandAccent(context: context)
        let isAmbient = !context.state.showsStrictCountdown
        let remaining = Self.upgradedDurationLabel(context.state.remainingLabel)
        let nextUp = Self.upgradedDurationLabel(context.state.nextUpSummary)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label(context.state.sessionLabel, systemImage: leadingIcon(context: context))
                    .font(.dsMetadata(weight: .bold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(context.state.constraintType)
                    .font(.dsMetadata(weight: .semibold))
                    .foregroundStyle(LiveActivityStyle.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(LiveActivityStyle.chipPlate))
            }

            Text(context.state.taskTitle)
                .font(.system(size: isAmbient ? 17 : 20, weight: .semibold))
                .foregroundStyle(LiveActivityStyle.textPrimary)
                .lineLimit(isAmbient ? 1 : 2)
                .minimumScaleFactor(0.85)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if context.state.isPaused {
                    Text("Paused • \(remaining)")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else if context.state.showsStrictCountdown {
                    Text(timerInterval: Date()...endDate(for: context), countsDown: true)
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text(remaining.isEmpty ? context.state.constraintType : remaining)
                        .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(accent)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 4)
                if !isAmbient || context.state.progressFraction > 0.01 {
                    Text("\(Int(context.state.progressFraction * 100))%")
                        .font(.dsCaption(weight: .semibold).monospacedDigit())
                        .foregroundStyle(LiveActivityStyle.textMuted)
                        .contentTransition(.numericText())
                }
            }

            if !isAmbient || context.state.progressFraction > 0.01 {
                LiveActivityLinearProgress(fraction: context.state.progressFraction, tint: accent)
            }

            if !nextUp.isEmpty {
                Text(nextUp)
                    .font(.dsMetadata())
                    .foregroundStyle(LiveActivityStyle.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            // Rest/Done only for real focus blocks — ambient Fluid Gap / Recovery
            // already fill the Lock Screen height budget without controls.
            if context.state.showsStrictCountdown, !context.state.isOnBreak {
                focusControlButtons
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .activityBackgroundTint(LiveActivityStyle.background)
    }

    /// Rewrites legacy `381m` / `381m until Dinner` labels that predate `durationString`.
    private static func upgradedDurationLabel(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if let pure = Int(trimmed.dropLast()), trimmed.hasSuffix("m"), !trimmed.contains("h"), !trimmed.contains(" ") {
            return pure.durationString
        }

        // Prefix form: "381m until Dinner" / "Next Up: 90m Fluid Gap · then X"
        var result = trimmed
        let pattern = #"\b(\d+)m\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return trimmed }
        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        let matches = regex.matches(in: result, range: range).reversed()
        for match in matches {
            guard match.numberOfRanges > 1,
                  let full = Range(match.range(at: 0), in: result),
                  let digits = Range(match.range(at: 1), in: result),
                  let minutes = Int(result[digits]),
                  minutes >= 60 else { continue }
            result.replaceSubrange(full, with: minutes.durationString)
        }
        return result
    }

    @ViewBuilder
    private var focusControlButtons: some View {
        HStack(spacing: 10) {
            Button(intent: WidgetPauseFocusIntent()) {
                Label("Rest", systemImage: "pause.circle.fill")
                    .font(.dsCaption(weight: .semibold))
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .tint(LiveActivityStyle.textSecondary)

            Button(intent: WidgetCompleteFocusIntent()) {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.dsCaption(weight: .semibold))
                    .lineLimit(1)
            }
            .buttonStyle(.borderedProminent)
            .tint(LiveActivityStyle.accent)
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
                        .foregroundStyle(LiveActivityStyle.accent)
                        .frame(width: 24, height: 24)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.sectionLabel.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(LiveActivityStyle.textMuted)
                        Text(nowPinTitle(context))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(LiveActivityStyle.textPrimary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(max(0, context.state.energyScore))%")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(LiveActivityStyle.accent)
                            .contentTransition(.numericText())
                        Text(energyLabel(context))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(LiveActivityStyle.textMuted)
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
                            .foregroundStyle(LiveActivityStyle.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 14, alignment: .leading)
                    }
                }
            } compactLeading: {
                Image(systemName: pinIcon(context))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiveActivityStyle.accent)
                    .frame(width: 18, height: 18)
            } compactTrailing: {
                Text("\(max(0, context.state.energyScore))%")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(LiveActivityStyle.accent)
                    .contentTransition(.numericText())
                    .frame(minWidth: 24, minHeight: 16)
            } minimal: {
                Image(systemName: pinIcon(context))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(LiveActivityStyle.accent)
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
        return "~\(PinNowSnapshotBuilder.compactDuration(minutes: minutes)) • \(energyLabel(context)) energy"
    }

    @ViewBuilder
    private func nowLockScreen(context: ActivityViewContext<NowPinActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: pinIcon(context))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LiveActivityStyle.accent)
                    .frame(width: 16, height: 16)

                Text(context.state.sectionLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(LiveActivityStyle.accent)
                    .lineLimit(1)
                    .frame(minHeight: 14)

                if !context.state.constraintLabel.isEmpty {
                    Text(context.state.constraintLabel)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(LiveActivityStyle.chipPlate))
                        .foregroundStyle(LiveActivityStyle.textSecondary)
                }

                Text("\(max(0, context.state.energyScore))%")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(LiveActivityStyle.textMuted)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .frame(minHeight: 14)
            }

            Text(nowPinTitle(context))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LiveActivityStyle.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(context.state.scheduleLabel.isEmpty ? pinDurationLabel(context) : context.state.scheduleLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(LiveActivityStyle.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 14)

                if !context.state.scheduleLabel.isEmpty {
                    pinRemainingLabel(context)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(LiveActivityStyle.accent)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                        .frame(minHeight: 14)
                }
            }

            pinProgressSection(context)

            if let footer = pinFooterLine(context) {
                Text(footer)
                    .font(.caption2)
                    .foregroundStyle(LiveActivityStyle.textMuted)
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
