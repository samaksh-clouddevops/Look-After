import ActivityKit
import WidgetKit
import SwiftUI
import LookAfterCore

private enum LiveActivityStyle {
    static let accent = DesignSystem.accentPrimary
    static let textPrimary = DesignSystem.textPrimary
    static let textSecondary = DesignSystem.textSecondary
    static let textMuted = DesignSystem.textMuted
    static let background = DesignSystem.backgroundPrimary

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
                        ProgressView(value: context.state.progressFraction)
                            .tint(islandAccent(context: context))
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

            ProgressView(value: context.state.progressFraction)
                .tint(accent)

            if !context.state.nextUpSummary.isEmpty {
                Text(context.state.nextUpSummary)
                    .font(.dsMetadata())
                    .foregroundColor(LiveActivityStyle.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .activityBackgroundTint(LiveActivityStyle.background)
    }
}

struct NowPinLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPinActivityAttributes.self) { context in
            nowLockScreen(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "sparkles")
                        .foregroundColor(LiveActivityStyle.textMuted)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NOW")
                            .font(.dsMetadata())
                            .foregroundColor(LiveActivityStyle.textMuted)
                        Text(context.state.topTaskTitle)
                            .font(.dsCaption(weight: .semibold))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.energyScore)%")
                        .font(.dsCaption(weight: .bold))
                        .foregroundColor(LiveActivityStyle.accent)
                }
            } compactLeading: {
                Image(systemName: "sparkles")
                    .foregroundColor(LiveActivityStyle.textMuted)
            } compactTrailing: {
                Text("\(context.state.energyScore)%")
                    .font(.dsMetadata(weight: .bold))
                    .foregroundColor(LiveActivityStyle.accent)
            } minimal: {
                Image(systemName: "sparkles")
                    .foregroundColor(LiveActivityStyle.textMuted)
            }
        }
    }

    @ViewBuilder
    private func nowLockScreen(context: ActivityViewContext<NowPinActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("NOW", systemImage: "sparkles")
                    .font(.dsMetadata(weight: .bold))
                    .foregroundColor(LiveActivityStyle.textSecondary)
                Spacer()
                Text("\(context.state.energyScore)% • \(context.state.energyLevel)")
                    .font(.dsMetadata(weight: .semibold))
                    .foregroundColor(LiveActivityStyle.textMuted)
            }

            Text(context.state.topTaskTitle)
                .font(.dsTitle())
                .foregroundColor(LiveActivityStyle.textPrimary)
                .lineLimit(2)

            Text(UserFacingCopy.sanitize(context.state.recommendation))
                .font(.dsBody())
                .foregroundColor(LiveActivityStyle.textSecondary)
                .lineLimit(2)

            HStack {
                Label("~\(context.state.estimatedMinutes) min", systemImage: "clock")
                Spacer()
                Text("Pinned to Lock Screen")
                    .font(.dsMetadata())
                    .foregroundColor(LiveActivityStyle.textMuted)
            }
            .font(.dsMetadata())
            .foregroundColor(LiveActivityStyle.textSecondary)
        }
        .padding(16)
        .activityBackgroundTint(LiveActivityStyle.background)
    }
}
