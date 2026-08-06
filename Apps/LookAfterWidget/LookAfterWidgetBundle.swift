import WidgetKit
import SwiftUI
import LookAfterCore

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
    static let surface = DesignSystem.backgroundSecondary
    static let accent = DesignSystem.accentPrimary
    static let textPrimary = DesignSystem.textPrimary
    static let textSecondary = DesignSystem.textSecondary
    static let textMuted = DesignSystem.textMuted
}

struct NowWidgetView: View {
    var entry: FlowWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(WidgetStyle.textMuted)
                Text("NOW")
                    .font(.dsMetadata(weight: .bold))
                    .foregroundColor(WidgetStyle.textSecondary)
                Spacer()
                energyBadge
            }

            if let title = entry.snapshot.topTaskTitle {
                Text(title)
                    .font(.dsBody(weight: .semibold))
                    .foregroundColor(WidgetStyle.textPrimary)
                    .lineLimit(3)
                if let mins = entry.snapshot.topTaskMinutes {
                    Text("~\(mins) min")
                        .font(.dsMetadata())
                        .foregroundColor(WidgetStyle.textMuted)
                }
            } else {
                Text("All clear")
                    .font(.dsBody(weight: .semibold))
                    .foregroundColor(WidgetStyle.textPrimary)
                Text("Nothing urgent right now")
                    .font(.dsMetadata())
                    .foregroundColor(WidgetStyle.textMuted)
            }

            Spacer(minLength: 0)

            Text("\(entry.snapshot.completedTodayCount) done today")
                .font(.dsMetadata())
                .foregroundColor(WidgetStyle.textMuted)
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
                        .foregroundColor(WidgetStyle.textMuted)
                    Text("Next step")
                        .font(.dsMetadata(weight: .bold))
                        .foregroundColor(WidgetStyle.textSecondary)
                }

                if let title = entry.snapshot.topTaskTitle {
                    Text(title)
                        .font(.dsHeadline())
                        .foregroundColor(WidgetStyle.textPrimary)
                        .lineLimit(2)
                } else {
                    Text("Your mind is clear")
                        .font(.dsHeadline())
                        .foregroundColor(WidgetStyle.textPrimary)
                }

                Text(entry.snapshot.recommendation)
                    .font(.dsMetadata())
                    .foregroundColor(WidgetStyle.textMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                energyRing
                Text(entry.snapshot.energyLevel)
                    .font(.dsMetadata(weight: .semibold))
                    .foregroundColor(WidgetStyle.textSecondary)
            }
        }
        .padding(14)
        .containerBackground(for: .widget) {
            WidgetStyle.background
        }
    }

    private var energyBadge: some View {
        Text("\(entry.snapshot.energyScore)%")
            .font(.dsMetadata(weight: .bold))
            .foregroundColor(DesignSystem.accentOnPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(WidgetStyle.accent))
    }

    private var energyRing: some View {
        ZStack {
            Circle()
                .stroke(DesignSystem.divider, lineWidth: 5)
                .frame(width: 52, height: 52)
            Circle()
                .trim(from: 0, to: Double(entry.snapshot.energyScore) / 100)
                .stroke(WidgetStyle.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: 52, height: 52)
                .rotationEffect(.degrees(-90))
            Text("\(entry.snapshot.energyScore)")
                .font(.dsCaption(weight: .bold))
                .foregroundColor(WidgetStyle.textPrimary)
        }
    }
}

struct NowWidget: Widget {
    let kind = "NowWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FlowWidgetProvider()) { entry in
            NowWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Step")
        .description("See your top task and energy level at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct EnergyWidgetView: View {
    var entry: FlowWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bolt.heart.fill")
                    .foregroundColor(WidgetStyle.textMuted)
                Text("ENERGY")
                    .font(.dsMetadata(weight: .bold))
                    .foregroundColor(WidgetStyle.textSecondary)
                Spacer()
                Text(entry.snapshot.energyLevel)
                    .font(.dsMetadata(weight: .semibold))
                    .foregroundColor(WidgetStyle.textSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(entry.snapshot.energyScore)")
                    .font(.dsDisplay())
                    .foregroundColor(WidgetStyle.textPrimary)
                Text("%")
                    .font(.dsCaption(weight: .semibold))
                    .foregroundColor(WidgetStyle.textMuted)
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
                .font(.dsMetadata())
                .foregroundColor(WidgetStyle.textMuted)
        }
        .padding(14)
        .containerBackground(for: .widget) {
            WidgetStyle.background
        }
    }

    private func metricRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(WidgetStyle.textMuted)
            Text(text)
                .font(.dsMetadata())
                .foregroundColor(WidgetStyle.textSecondary)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.square.fill")
                    .foregroundColor(WidgetStyle.textMuted)
                Text("TASKS")
                    .font(.dsMetadata(weight: .bold))
                    .foregroundColor(WidgetStyle.textSecondary)
                Spacer()
                Text("\(entry.snapshot.completedTodayCount) done")
                    .font(.dsMetadata())
                    .foregroundColor(WidgetStyle.textMuted)
            }

            if entry.snapshot.tasks.isEmpty {
                Text("No active tasks")
                    .font(.dsBody(weight: .semibold))
                    .foregroundColor(WidgetStyle.textSecondary)
            } else {
                ForEach(entry.snapshot.tasks.prefix(3)) { task in
                    HStack(spacing: 8) {
                        Circle()
                            .stroke(DesignSystem.border, lineWidth: 1.5)
                            .frame(width: 14, height: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(task.title)
                                .font(.dsMetadata(weight: .semibold))
                                .foregroundColor(WidgetStyle.textPrimary)
                                .lineLimit(1)
                            Text("\(task.estimatedMinutes)m • \(task.priorityLabel)")
                                .font(.dsMetadata())
                                .foregroundColor(WidgetStyle.textMuted)
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
    }
}
