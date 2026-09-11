import WidgetKit
import SwiftUI
import LookAfterCore
#if canImport(AppIntents)
import AppIntents
#endif

struct FlowWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FlowWidgetEntry {
        FlowWidgetEntry(date: Date(), snapshot: sampleSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (FlowWidgetEntry) -> Void) {
        completion(FlowWidgetEntry(date: Date(), snapshot: AppGroupWidgetStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FlowWidgetEntry>) -> Void) {
        let snapshot = AppGroupWidgetStore.load()
        let entry = FlowWidgetEntry(date: Date(), snapshot: snapshot)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private var sampleSnapshot: WidgetSnapshot {
        WidgetSnapshot(
            topTaskTitle: "Review project notes",
            topTaskMinutes: 25,
            energyScore: 78,
            energyLevel: "High",
            recommendation: "Your energy is high — tackle this while focus is strong.",
            completedTodayCount: 2,
            activeTaskCount: 5,
            sleepHours: 7.2,
            stepCount: 4200,
            tasks: [
                WidgetTaskItem(id: "1", title: "Review project notes", estimatedMinutes: 25, priorityLabel: "High"),
                WidgetTaskItem(id: "2", title: "Reply to emails", estimatedMinutes: 15, priorityLabel: "Medium"),
            ]
        )
    }
}

struct FlowWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

private enum WidgetStyle {
    static let background = DesignSystem.backgroundPrimary
    static let surface = DesignSystem.contentSurface
    static let surfaceElevated = DesignSystem.contentSurfaceElevated
    /// Brand green — same as `DesignSystem.accentPrimary` / `5A9E3F`.
    static let accent = DesignSystem.accentPrimary
    static let textPrimary = DesignSystem.textPrimary
    static let textSecondary = DesignSystem.textSecondary
    static let textMuted = DesignSystem.textMuted
}

struct NowWidgetView: View {
    var entry: FlowWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var usesFullColor: Bool { renderingMode == .fullColor }

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumView
            default:
                smallView
            }
        }
        .widgetURL(URL(string: "lookafter://today"))
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(usesFullColor ? WidgetStyle.textMuted : .secondary)
                    .widgetAccentable()
                Text(LookAfterL10n.widgetNow)
                    .font(.dsMetadata(weight: .bold))
                    .foregroundStyle(usesFullColor ? WidgetStyle.textSecondary : .secondary)
                    .widgetAccentable()
                Spacer()
                energyBadge
            }

            if let title = entry.snapshot.topTaskTitle {
                Text(title)
                    .font(.dsBody(weight: .semibold))
                    .foregroundStyle(usesFullColor ? WidgetStyle.textPrimary : .primary)
                    .lineLimit(3)
                if let mins = entry.snapshot.topTaskMinutes {
                    Text("~\(mins) min")
                        .font(.dsMetadata().monospacedDigit())
                        .foregroundStyle(usesFullColor ? WidgetStyle.textMuted : .secondary)
                        .contentTransition(.numericText())
                        .animation(PremiumMotion.snappy(reduceMotion: reduceMotion), value: mins)
                }
            } else {
                Text(LookAfterL10n.widgetAllClear)
                    .font(.dsBody(weight: .semibold))
                    .foregroundStyle(usesFullColor ? WidgetStyle.textPrimary : .primary)
                Text(LookAfterL10n.widgetNothingUrgent)
                    .font(.dsMetadata())
                    .foregroundStyle(usesFullColor ? WidgetStyle.textMuted : .secondary)
            }

            Spacer(minLength: 0)

            if entry.snapshot.resolvedTopTaskTitle != nil {
                Button(intent: WidgetStartHeroTaskIntent()) {
                    Text(LookAfterL10n.widgetStartFocus)
                        .font(.dsMetadata(weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(WidgetStyle.accent)
            }

            Text(LookAfterL10n.widgetDoneToday(count: entry.snapshot.completedTodayCount))
                .font(.dsMetadata().monospacedDigit())
                .foregroundStyle(usesFullColor ? WidgetStyle.textMuted : .secondary)
                .contentTransition(.numericText())
                .animation(PremiumMotion.snappy(reduceMotion: reduceMotion), value: entry.snapshot.completedTodayCount)
        }
        .padding(14)
        .containerBackground(for: .widget) {
            WidgetStyle.background
        }
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(usesFullColor ? WidgetStyle.textMuted : .secondary)
                        .widgetAccentable()
                    Text(LookAfterL10n.widgetNextStep)
                        .font(.dsMetadata(weight: .bold))
                        .foregroundStyle(usesFullColor ? WidgetStyle.textSecondary : .secondary)
                        .widgetAccentable()
                }

                if let title = entry.snapshot.topTaskTitle {
                    Text(title)
                        .font(.dsHeadline())
                        .foregroundStyle(usesFullColor ? WidgetStyle.textPrimary : .primary)
                        .lineLimit(2)
                } else {
                    Text(LookAfterL10n.widgetMindClear)
                        .font(.dsHeadline())
                        .foregroundStyle(usesFullColor ? WidgetStyle.textPrimary : .primary)
                }

                Text(entry.snapshot.recommendation)
                    .font(.dsMetadata())
                    .foregroundStyle(usesFullColor ? WidgetStyle.textMuted : .secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                energyRing
                Text(entry.snapshot.energyLevel)
                    .font(.dsMetadata(weight: .semibold))
                    .foregroundStyle(usesFullColor ? WidgetStyle.textSecondary : .secondary)
                    .widgetAccentable()
            }
        }
        .padding(14)
        .containerBackground(for: .widget) {
            WidgetStyle.background
        }
    }

    private var energyBadge: some View {
        Text("\(entry.snapshot.energyScore)%")
            .font(.dsMetadata(weight: .bold).monospacedDigit())
            .contentTransition(.numericText())
            .animation(PremiumMotion.snappy(reduceMotion: reduceMotion), value: entry.snapshot.energyScore)
            .modifier(EnergyBadgeChrome(usesFullColor: usesFullColor))
            .widgetAccentable()
    }

    private var energyRing: some View {
        ZStack {
            Circle()
                .stroke(usesFullColor ? DesignSystem.divider : Color.primary.opacity(0.2), lineWidth: 5)
                .frame(width: 52, height: 52)
            Circle()
                .trim(from: 0, to: Double(entry.snapshot.energyScore) / 100)
                .stroke(
                    usesFullColor ? WidgetStyle.accent : Color.primary,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .frame(width: 52, height: 52)
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            Text("\(entry.snapshot.energyScore)")
                .font(.dsCaption(weight: .bold).monospacedDigit())
                .foregroundStyle(usesFullColor ? WidgetStyle.textPrimary : .primary)
                .contentTransition(.numericText())
                .animation(PremiumMotion.snappy(reduceMotion: reduceMotion), value: entry.snapshot.energyScore)
                .widgetAccentable()
        }
    }
}

private struct EnergyBadgeChrome: ViewModifier {
    let usesFullColor: Bool

    func body(content: Content) -> some View {
        if usesFullColor {
            content
                .foregroundStyle(DesignSystem.accentOnPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(WidgetStyle.accent))
        } else {
            // Vibrant / accented: let the system material carry the plate; keep the score accentable.
            content
                .foregroundStyle(.primary)
        }
    }
}

struct NowWidget: Widget {
    let kind = "NowWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FlowWidgetProvider()) { entry in
            NowWidgetView(entry: entry)
        }
        .configurationDisplayName(LookAfterL10n.widgetConfigNowName)
        .description(LookAfterL10n.widgetConfigNowDescription)
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct EnergyWidgetView: View {
    var entry: FlowWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var usesFullColor: Bool { renderingMode == .fullColor }
    private var energyValue: Double { Double(entry.snapshot.energyScore) }

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                accessoryRectangular
            case .accessoryInline:
                accessoryInline
            default:
                homeSmall
            }
        }
        .widgetURL(URL(string: "lookafter://today"))
    }

    private var homeSmall: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bolt.heart.fill")
                    .foregroundStyle(usesFullColor ? WidgetStyle.textMuted : .secondary)
                    .widgetAccentable()
                Text(LookAfterL10n.widgetEnergy)
                    .font(.dsMetadata(weight: .bold))
                    .foregroundStyle(usesFullColor ? WidgetStyle.textSecondary : .secondary)
                    .widgetAccentable()
                Spacer()
                Text(entry.snapshot.energyLevel)
                    .font(.dsMetadata(weight: .semibold))
                    .foregroundStyle(usesFullColor ? WidgetStyle.textSecondary : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(WidgetStyle.surfaceElevated))
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(entry.snapshot.energyScore)")
                    .font(.dsDisplay().monospacedDigit())
                    .foregroundStyle(usesFullColor ? WidgetStyle.textPrimary : .primary)
                    .contentTransition(.numericText())
                    .animation(PremiumMotion.snappy(reduceMotion: reduceMotion), value: entry.snapshot.energyScore)
                    .widgetAccentable()
                Text("%")
                    .font(.dsCaption(weight: .semibold))
                    .foregroundStyle(usesFullColor ? WidgetStyle.textMuted : .secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let sleep = entry.snapshot.sleepHours {
                    metricRow(icon: "bed.double.fill", text: String(format: "%.1fh sleep", sleep))
                }
                if let steps = entry.snapshot.stepCount {
                    metricRow(icon: "figure.walk", text: "\(steps) steps")
                }
                if let hrv = entry.snapshot.hrvMs {
                    metricRow(icon: "waveform.path.ecg", text: "HRV \(hrv) ms")
                }
            }

            Spacer(minLength: 0)

            Text("\(entry.snapshot.activeTaskCount) active • \(entry.snapshot.completedTodayCount) done")
                .font(.dsMetadata().monospacedDigit())
                .foregroundStyle(usesFullColor ? WidgetStyle.textMuted : .secondary)
                .contentTransition(.numericText())
                .animation(
                    PremiumMotion.snappy(reduceMotion: reduceMotion),
                    value: entry.snapshot.activeTaskCount + entry.snapshot.completedTodayCount
                )
        }
        .padding(14)
        .containerBackground(for: .widget) {
            WidgetStyle.background
        }
    }

    private var accessoryRectangular: some View {
        Gauge(value: energyValue, in: 0...100) {
            Label("Energy", systemImage: "bolt.heart.fill")
                .widgetAccentable()
        } currentValueLabel: {
            Text("\(entry.snapshot.energyScore)")
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText())
                .animation(PremiumMotion.snappy(reduceMotion: reduceMotion), value: entry.snapshot.energyScore)
                .widgetAccentable()
        } minimumValueLabel: {
            Text("0")
        } maximumValueLabel: {
            Text("100")
        }
        .gaugeStyle(.accessoryLinearCapacity)
        .containerBackground(for: .widget) {
            AccessoryWidgetBackground()
        }
    }

    private var accessoryInline: some View {
        Label {
            Text("\(entry.snapshot.energyScore)% \(entry.snapshot.energyLevel)")
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(PremiumMotion.snappy(reduceMotion: reduceMotion), value: entry.snapshot.energyScore)
        } icon: {
            Image(systemName: "bolt.heart.fill")
        }
        .widgetAccentable()
    }

    private func metricRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(usesFullColor ? WidgetStyle.textMuted : .secondary)
            Text(text)
                .font(.dsMetadata())
                .foregroundStyle(usesFullColor ? WidgetStyle.textSecondary : .secondary)
        }
    }
}

struct EnergyWidget: Widget {
    let kind = "EnergyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FlowWidgetProvider()) { entry in
            EnergyWidgetView(entry: entry)
        }
        .configurationDisplayName("Energy Pulse")
        .description("Energy score plus sleep, steps, and HRV from Apple Watch.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

struct TasksWidgetView: View {
    var entry: FlowWidgetEntry
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var usesFullColor: Bool { renderingMode == .fullColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.square.fill")
                    .foregroundStyle(usesFullColor ? WidgetStyle.textMuted : .secondary)
                    .widgetAccentable()
                Text(LookAfterL10n.widgetTasks)
                    .font(.dsMetadata(weight: .bold))
                    .foregroundStyle(usesFullColor ? WidgetStyle.textSecondary : .secondary)
                    .widgetAccentable()
                Spacer()
                Text("\(entry.snapshot.completedTodayCount) done")
                    .font(.dsMetadata().monospacedDigit())
                    .foregroundStyle(usesFullColor ? WidgetStyle.textMuted : .secondary)
                    .contentTransition(.numericText())
                    .animation(PremiumMotion.snappy(reduceMotion: reduceMotion), value: entry.snapshot.completedTodayCount)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(WidgetStyle.surfaceElevated))
            }

            if entry.snapshot.tasks.isEmpty {
                Text(LookAfterL10n.widgetNoActiveTasks)
                    .font(.dsBody(weight: .semibold))
                    .foregroundStyle(usesFullColor ? WidgetStyle.textSecondary : .secondary)
            } else {
                ForEach(entry.snapshot.tasks.prefix(3)) { task in
                    HStack(spacing: 8) {
                        Circle()
                            .stroke(usesFullColor ? DesignSystem.border : Color.primary.opacity(0.35), lineWidth: 1.5)
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(WidgetStyle.surface))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(task.title)
                                .font(.dsMetadata(weight: .semibold))
                                .foregroundStyle(usesFullColor ? WidgetStyle.textPrimary : .primary)
                                .lineLimit(1)
                            Text("\(task.estimatedMinutes)m • \(task.priorityLabel)")
                                .font(.dsMetadata().monospacedDigit())
                                .foregroundStyle(usesFullColor ? WidgetStyle.textMuted : .secondary)
                                .contentTransition(.numericText())
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .containerBackground(for: .widget) {
            WidgetStyle.background
        }
    }
}

struct TasksWidget: Widget {
    let kind = "TasksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FlowWidgetProvider()) { entry in
            TasksWidgetView(entry: entry)
        }
        .configurationDisplayName("Task Glance")
        .description("Top 3 active tasks on your home screen.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct LookAfterWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowWidget()
        EnergyWidget()
        TasksWidget()
        FocusLiveActivity()
        NowPinLiveActivity()
        LookAfterCaptureControl()
        LookAfterStartFocusControl()
    }
}
