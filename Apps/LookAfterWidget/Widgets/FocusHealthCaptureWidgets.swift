import WidgetKit
import SwiftUI
import LookAfterCore

// MARK: - Focus

struct FocusWidgetView: View {
    var entry: ExecutiveWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var focus: WidgetFocusState {
        entry.snapshot.focus ?? .idle
    }

    var body: some View {
        WidgetRootContainer {
            VStack(alignment: .leading, spacing: WidgetChrome.gap) {
                WidgetEyebrow(
                    focus.isOnBreak ? "Break" : "Focus",
                    systemImage: focus.isOnBreak ? "cup.and.saucer.fill" : "timer",
                    tint: DesignSystem.focus
                )
                if focus.isActive {
                    WidgetPrimaryText(focus.taskTitle ?? "Deep work", lineLimit: family == .systemSmall ? 2 : 2)
                    if let remaining = focus.remainingLabel {
                        Text(focus.isPaused ? "Paused · \(remaining)" : remaining)
                            .font(.system(size: family == .systemSmall ? 22 : 28, weight: .bold, design: .monospaced))
                            .foregroundStyle(DesignSystem.accentPrimary)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
                } else {
                    WidgetEmptyState(title: "Start focus", detail: "Open Look After when you're ready.")
                }
                Spacer(minLength: 0)
            }
        }
        .widgetURL(LookAfterDeepLink.focus)
        .accessibilityLabel(focus.isActive
            ? "Focus on \(focus.taskTitle ?? "task"). \(focus.remainingLabel ?? "")"
            : "Start focus session")
    }
}

struct FocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LookAfterWidgetKind.focus, provider: ExecutiveWidgetProvider()) { entry in
            FocusWidgetView(entry: entry)
        }
        .configurationDisplayName("Focus")
        .description("Deep work countdown or a calm start control.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Health

struct HealthWidgetView: View {
    var entry: ExecutiveWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        WidgetRootContainer {
            VStack(alignment: .leading, spacing: WidgetChrome.gap) {
                HStack {
                    WidgetEyebrow("Energy", systemImage: "bolt.heart.fill", tint: DesignSystem.health)
                    Spacer(minLength: 0)
                    Text(entry.snapshot.energyLevel)
                        .font(.dsCaption(weight: .semibold))
                        .foregroundStyle(DesignSystem.textSecondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(entry.snapshot.energyScore)")
                        .font(.dsDisplay())
                        .foregroundStyle(DesignSystem.textPrimary)
                    Text("%")
                        .font(.dsCaption(weight: .semibold))
                        .foregroundStyle(DesignSystem.textMuted)
                }

                if let sleep = entry.snapshot.sleepHours {
                    metric(icon: "bed.double.fill", text: String(format: "%.1fh sleep", sleep))
                }
                if family != .systemSmall, let recovery = entry.snapshot.recoveryLabel {
                    metric(icon: "leaf.fill", text: recovery)
                } else if family == .systemSmall, let recovery = entry.snapshot.recoveryLabel {
                    WidgetMetaText(recovery, lineLimit: 1)
                } else if let hrv = entry.snapshot.hrvMs {
                    metric(icon: "waveform.path.ecg", text: "HRV \(hrv) ms")
                }

                Spacer(minLength: 0)
            }
        }
        .widgetURL(LookAfterDeepLink.health)
        .accessibilityLabel("Energy \(entry.snapshot.energyScore) percent, \(entry.snapshot.energyLevel)")
    }

    private func metric(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignSystem.health)
            Text(text)
                .font(.dsMetadata())
                .foregroundStyle(DesignSystem.textSecondary)
                .lineLimit(1)
        }
    }
}

struct HealthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LookAfterWidgetKind.health, provider: ExecutiveWidgetProvider()) { entry in
            HealthWidgetView(entry: entry)
        }
        .configurationDisplayName("Energy & Recovery")
        .description("Sleep, energy, and recovery — only metrics that matter.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Capture

struct CaptureWidgetView: View {
    var entry: ExecutiveWidgetEntry

    var body: some View {
        WidgetRootContainer {
            VStack(spacing: WidgetChrome.gapLoose) {
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .fill(DesignSystem.accentPrimary.opacity(0.2))
                        .frame(width: 56, height: 56)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(DesignSystem.accentOnPrimary)
                        .padding(14)
                        .background(Circle().fill(DesignSystem.accentPrimary))
                }
                Text("Capture")
                    .font(.dsHeadline())
                    .foregroundStyle(DesignSystem.textPrimary)
                Text("Voice · note · task")
                    .font(.dsMetadata())
                    .foregroundStyle(DesignSystem.textMuted)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .widgetURL(LookAfterDeepLink.capture(mode: "voice"))
        .accessibilityLabel("Capture. Voice, note, or task.")
        .accessibilityHint("Opens Look After to capture")
    }
}

struct CaptureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LookAfterWidgetKind.capture, provider: ExecutiveWidgetProvider()) { entry in
            CaptureWidgetView(entry: entry)
        }
        .configurationDisplayName("Capture")
        .description("One tap to voice, note, or task — open instantly.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
