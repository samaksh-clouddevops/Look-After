import ActivityKit
import WidgetKit
import SwiftUI
import LifeOSCore

private enum LiveActivityStyle {
    static let accent = DesignSystem.accentPrimary
    static let textPrimary = DesignSystem.textPrimary
    static let textSecondary = DesignSystem.textSecondary
    static let textMuted = DesignSystem.textMuted
    static let background = DesignSystem.backgroundPrimary
}

struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            focusLockScreen(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isOnBreak ? "cup.and.saucer.fill" : "brain.head.profile")
                        .foregroundColor(context.state.isOnBreak ? LiveActivityStyle.textSecondary : LiveActivityStyle.accent)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.sessionLabel)
                            .font(.dsMetadata())
                            .foregroundColor(LiveActivityStyle.textMuted)
                        Text(context.state.taskTitle)
                            .font(.dsCaption(weight: .semibold))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isPaused {
                        Text(context.state.remainingLabel)
                            .font(.dsCaption(weight: .semibold).monospacedDigit())
                            .foregroundColor(LiveActivityStyle.accent)
                    } else {
                        Text(timerInterval: Date()...context.state.sessionEndDate, countsDown: true)
                            .font(.dsCaption(weight: .semibold).monospacedDigit())
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(LiveActivityStyle.accent)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isOnBreak ? "cup.and.saucer.fill" : "timer")
                    .foregroundColor(LiveActivityStyle.textSecondary)
            } compactTrailing: {
                if context.state.isPaused {
                    Text(context.state.remainingLabel)
                        .font(.dsMetadata().monospacedDigit())
                        .foregroundColor(LiveActivityStyle.accent)
                } else {
                    Text(timerInterval: Date()...context.state.sessionEndDate, countsDown: true)
                        .font(.dsMetadata().monospacedDigit())
                        .frame(width: 40)
                        .foregroundColor(LiveActivityStyle.accent)
                }
            } minimal: {
                Image(systemName: "timer")
                    .foregroundColor(LiveActivityStyle.accent)
            }
        }
    }

    @ViewBuilder
    private func focusLockScreen(context: ActivityViewContext<FocusActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(context.state.sessionLabel, systemImage: context.state.isOnBreak ? "cup.and.saucer.fill" : "brain.head.profile")
                    .font(.dsMetadata(weight: .bold))
                    .foregroundColor(context.state.isOnBreak ? LiveActivityStyle.textSecondary : LiveActivityStyle.accent)
                Spacer()
                Text("Session \(context.attributes.sessionNumber)")
                    .font(.dsMetadata())
                    .foregroundColor(LiveActivityStyle.textMuted)
            }

            Text(context.state.taskTitle)
                .font(.dsHeadline())
                .foregroundColor(LiveActivityStyle.textPrimary)
                .lineLimit(2)

            HStack {
                if context.state.isPaused {
                    Text("Paused • \(context.state.remainingLabel) left")
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(LiveActivityStyle.accent)
                } else {
                    Text(timerInterval: Date()...context.state.sessionEndDate, countsDown: true)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(LiveActivityStyle.accent)
                }
                Spacer()
                if context.state.isPaused {
                    Image(systemName: "pause.circle.fill")
                        .font(.title2)
                        .foregroundColor(LiveActivityStyle.textSecondary)
                }
            }

            Text("Timer pinned — open \(UserFacingCopy.productName) to control.")
                .font(.dsMetadata())
                .foregroundColor(LiveActivityStyle.textMuted)
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
