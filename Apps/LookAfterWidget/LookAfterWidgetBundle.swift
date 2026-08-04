import WidgetKit
import SwiftUI
import LookAfterCore

// MARK: - V1 provider (migration overlap)

struct FlowWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FlowWidgetEntry {
        FlowWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (FlowWidgetEntry) -> Void) {
        completion(FlowWidgetEntry(date: Date(), snapshot: WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FlowWidgetEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.load()
        let entry = FlowWidgetEntry(date: Date(), snapshot: snapshot)
        let next = Calendar.current.date(byAdding: .minute, value: 20, to: Date()) ?? Date().addingTimeInterval(1200)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct FlowWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - V1 wrappers map to V2 chrome

struct NowWidgetView: View {
    var entry: FlowWidgetEntry
    var body: some View {
        RecommendationWidgetView(entry: ExecutiveWidgetEntry(date: entry.date, snapshot: entry.snapshot))
    }
}

struct EnergyWidgetView: View {
    var entry: FlowWidgetEntry
    var body: some View {
        HealthWidgetView(entry: ExecutiveWidgetEntry(date: entry.date, snapshot: entry.snapshot))
    }
}

struct TasksWidgetView: View {
    var entry: FlowWidgetEntry
    var body: some View {
        TodayWidgetView(entry: ExecutiveWidgetEntry(date: entry.date, snapshot: entry.snapshot))
    }
}

struct NowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LookAfterWidgetKind.nowV1, provider: FlowWidgetProvider()) { entry in
            NowWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Step")
        .description("See your top task and energy level at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct EnergyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LookAfterWidgetKind.energyV1, provider: FlowWidgetProvider()) { entry in
            EnergyWidgetView(entry: entry)
        }
        .configurationDisplayName("Energy Pulse")
        .description("Energy score plus sleep and recovery.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

struct TasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LookAfterWidgetKind.tasksV1, provider: FlowWidgetProvider()) { entry in
            TasksWidgetView(entry: entry)
        }
        .configurationDisplayName("Task Glance")
        .description("Your day at a glance.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Bundle

@main
struct LookAfterWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecommendationWidget()
        TodayWidget()
        FocusWidget()
        HealthWidget()
        CaptureWidget()
        NowWidget()
        EnergyWidget()
        TasksWidget()
        FocusLiveActivity()
        NowPinLiveActivity()
    }
}
