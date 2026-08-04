import WidgetKit
import SwiftUI
import AppIntents
import LookAfterCore

// MARK: - Focus

struct FocusWidgetView: View {
    var entry: ExecutiveWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var focus: WidgetFocusState {
        entry.snapshot.focus ?? .idle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetChrome.gap) {
            WidgetEyebrow(
                focus.isOnBreak ? "Break" : "Focus",
                systemImage: focus.isOnBreak ? "cup.and.saucer.fill" : "timer",
                tint: DesignSystem.focus
            )
            if focus.isActive {
                WidgetPrimaryText(focus.taskTitle ?? "Deep work", lineLimit: 2)
                if let remaining = focus.remainingLabel {
                    Text(focus.isPaused ? "Paused · \(remaining)" : remaining)
                        .font(.system(size: family == .systemSmall ? 22 : 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignSystem.accentPrimary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                if family != .systemSmall {
                    HStack(spacing: 8) {
                        Button(intent: PauseFocusIntent()) {
                            Text(focus.isPaused ? "Resume" : "Pause")
                                .font(.dsCaption(weight: .bold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().strokeBorder(DesignSystem.borderPrimary, lineWidth: 1))
                        }.buttonStyle(.plain)
                        Button(intent: EndFocusIntent()) {
                            Text("End")
                                .font(.dsCaption(weight: .bold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(DesignSystem.accentPrimary))
                                .foregroundStyle(DesignSystem.accentOnPrimary)
                        }.buttonStyle(.plain)
                    }
                }
            } else {
                WidgetEmptyState(title: "Start focus", detail: "Protect a deep work block.")
                Button(intent: StartFocusIntent(taskID: entry.snapshot.resolvedRecommendation.taskID)) {
                    Text("Start focus")
                        .font(.dsCaption(weight: .bold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(DesignSystem.accentPrimary))
                        .foregroundStyle(DesignSystem.accentOnPrimary)
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .lookAfterWidgetChrome()
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

    private var hasHealth: Bool { entry.snapshot.hasHealthData }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularBody
            case .accessoryInline:
                inlineBody
            case .accessoryRectangular:
                rectangularBody
            default:
                homeBody
            }
        }
        .widgetURL(LookAfterDeepLink.health)
        .accessibilityLabel(accessibilityCopy)
    }

    private var circularBody: some View {
        ZStack {
            if hasHealth {
                Gauge(value: Double(entry.snapshot.energyScore), in: 0...100) {
                    Text("E")
                } currentValueLabel: {
                    Text("\(entry.snapshot.energyScore)")
                        .font(.system(size: 14, weight: .bold))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(DesignSystem.accentPrimary)
            } else {
                Image(systemName: "heart")
                    .font(.title3)
                    .foregroundStyle(DesignSystem.textMuted)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var inlineBody: some View {
        Group {
            if hasHealth {
                let sleep = entry.snapshot.sleepHours.map { String(format: "%.1fh" , $0) } ?? "—"
                Text("\(entry.snapshot.energyScore)% · \(sleep)")
            } else {
                Text("Connect Health")
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var rectangularBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            if hasHealth {
                Text("Energy \(entry.snapshot.energyScore)%")
                    .font(.headline)
                if let sleep = entry.snapshot.sleepHours {
                    Text(String(format: "%.1fh sleep", sleep)).font(.caption)
                }
            } else {
                Text("Health offline").font(.headline)
                Text("Open Look After").font(.caption)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var homeBody: some View {
        VStack(alignment: .leading, spacing: WidgetChrome.gap) {
            HStack {
                WidgetEyebrow("Energy", systemImage: "bolt.heart.fill", tint: DesignSystem.health)
                Spacer(minLength: 0)
                if hasHealth {
                    Text(entry.snapshot.energyLevel)
                        .font(.dsCaption(weight: .semibold))
                        .foregroundStyle(DesignSystem.textSecondary)
                }
            }
            if hasHealth {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(entry.snapshot.energyScore)")
                        .font(.dsDisplay())
                        .foregroundStyle(DesignSystem.textPrimary)
                    Text("%").font(.dsCaption(weight: .semibold)).foregroundStyle(DesignSystem.textMuted)
                }
                if let sleep = entry.snapshot.sleepHours {
                    metric(icon: "bed.double.fill", text: String(format: "%.1fh sleep", sleep))
                }
                if let recovery = entry.snapshot.recoveryLabel {
                    WidgetMetaText(recovery, lineLimit: 1)
                } else if let hrv = entry.snapshot.hrvMs {
                    metric(icon: "waveform.path.ecg", text: "HRV \(hrv) ms")
                }
                if let water = entry.snapshot.hydrationMlToday, water > 0 {
                    metric(icon: "drop.fill", text: "\(Int(water)) ml water")
                }
            } else {
                WidgetEmptyState(
                    title: "No health data",
                    detail: "Connect Health in Look After — we only show real readings."
                )
            }
            Spacer(minLength: 0)
        }
        .lookAfterWidgetChrome()
    }

    private func metric(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold)).foregroundStyle(DesignSystem.health)
            Text(text).font(.dsMetadata()).foregroundStyle(DesignSystem.textSecondary).lineLimit(1)
        }
    }

    private var accessibilityCopy: String {
        if hasHealth {
            return "Energy \(entry.snapshot.energyScore) percent, \(entry.snapshot.energyLevel)"
        }
        return "No health data. Open Look After to connect Health."
    }
}

struct HealthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LookAfterWidgetKind.health, provider: ExecutiveWidgetProvider()) { entry in
            HealthWidgetView(entry: entry)
        }
        .configurationDisplayName("Energy & Recovery")
        .description("Sleep, energy, and recovery — only metrics that matter.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

// MARK: - Capture

struct CaptureWidgetView: View {
    var entry: ExecutiveWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumBody
            } else {
                smallBody
            }
        }
    }

    private var smallBody: some View {
        VStack(spacing: WidgetChrome.gapLoose) {
            Spacer(minLength: 0)
            captureGlyph
            Text("Capture").font(.dsHeadline()).foregroundStyle(DesignSystem.textPrimary)
            Text("Voice · note · task").font(.dsMetadata()).foregroundStyle(DesignSystem.textMuted)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .lookAfterWidgetChrome()
        .widgetURL(LookAfterDeepLink.capture(mode: "voice"))
        .accessibilityLabel("Capture. Voice, note, or task.")
    }

    private var mediumBody: some View {
        HStack(spacing: 12) {
            modeButton(title: "Voice", icon: "mic.fill", mode: "voice")
            modeButton(title: "Note", icon: "square.and.pencil", mode: "text")
            modeButton(title: "Task", icon: "checkmark.circle", mode: "task")
        }
        .lookAfterWidgetChrome()
        .accessibilityLabel("Capture modes: Voice, Note, Task")
    }

    private func modeButton(title: String, icon: String, mode: String) -> some View {
        Link(destination: LookAfterDeepLink.capture(mode: mode)) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DesignSystem.accentOnPrimary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(DesignSystem.accentPrimary))
                Text(title)
                    .font(.dsCaption(weight: .semibold))
                    .foregroundStyle(DesignSystem.textPrimary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var captureGlyph: some View {
        ZStack {
            Circle().fill(DesignSystem.accentPrimary.opacity(0.2)).frame(width: 56, height: 56)
            Image(systemName: "mic.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(DesignSystem.accentOnPrimary)
                .padding(14)
                .background(Circle().fill(DesignSystem.accentPrimary))
        }
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

// MARK: - Medication

struct MedicationWidgetView: View {
    var entry: ExecutiveWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var med: WidgetMedicationStatus {
        entry.snapshot.medication ?? .none
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetChrome.gap) {
            WidgetEyebrow("Medication", systemImage: "pills.fill", tint: DesignSystem.health)
            if med.hasMedication {
                WidgetPrimaryText(med.name ?? "Dose", lineLimit: 2)
                if let time = med.timeLabel {
                    WidgetMetaText(med.isTaken ? "Taken · \(time)" : "Due · \(time)")
                }
                if !med.isTaken {
                    Button(intent: MarkMedicationTakenIntent(medicationID: med.id)) {
                        Text("Mark taken")
                            .font(.dsCaption(weight: .bold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(DesignSystem.accentPrimary))
                            .foregroundStyle(DesignSystem.accentOnPrimary)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(DesignSystem.accentPrimary)
                        Text("Taken").font(.dsCaption(weight: .semibold)).foregroundStyle(DesignSystem.textSecondary)
                    }
                }
                WidgetMetaText("Status only — not medical advice.", lineLimit: 1)
            } else {
                WidgetEmptyState(title: "No doses due", detail: "Add medications in Look After.")
            }
            Spacer(minLength: 0)
        }
        .lookAfterWidgetChrome()
        .widgetURL(LookAfterDeepLink.medication)
        .accessibilityLabel(med.hasMedication
            ? "\(med.name ?? "Medication"). \(med.isTaken ? "Taken" : "Due") \(med.timeLabel ?? "")"
            : "No medication due")
    }
}

struct MedicationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LookAfterWidgetKind.medication, provider: ExecutiveWidgetProvider()) { entry in
            MedicationWidgetView(entry: entry)
        }
        .configurationDisplayName("Medication")
        .description("Next dose and taken status. Deterministic only — never advice.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}
