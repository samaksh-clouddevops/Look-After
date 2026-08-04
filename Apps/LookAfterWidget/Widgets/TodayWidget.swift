import WidgetKit
import SwiftUI
import LookAfterCore

/// P0 — What's next on my day? (timeline, not a task dump)
struct TodayWidgetView: View {
    var entry: ExecutiveWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var today: WidgetTodaySummary {
        entry.snapshot.today ?? .empty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetChrome.gap) {
            WidgetEyebrow("Today", systemImage: "calendar")

            if family == .systemLarge {
                largeBody
            } else {
                mediumBody
            }

            if entry.snapshot.isStale {
                WidgetStaleBanner()
            }
            Spacer(minLength: 0)
        }
        .lookAfterWidgetChrome()
        .widgetURL(LookAfterDeepLink.today)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityCopy)
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let time = today.nextEventTimeLabel, let title = today.nextEventTitle {
                beatRow(time: time, title: title, detail: nil)
            }
            if let task = today.nextTaskTitle {
                beatRow(time: "Next", title: task, detail: nil)
            }
            if today.nextEventTitle == nil && today.nextTaskTitle == nil {
                WidgetEmptyState(title: "Day is open", detail: "No fixed events right now.")
            }
            if let free = today.freeMinutes {
                WidgetMetaText("Free \(free) min\(today.capacityLabel.map { " · \($0)" } ?? "")")
            }
        }
    }

    private var largeBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            let beats = Array(today.beats.prefix(4))
            if beats.isEmpty {
                mediumBody
            } else {
                ForEach(beats) { beat in
                    beatRow(time: beat.timeLabel, title: beat.title, detail: beat.detail)
                }
            }
            if let free = today.freeMinutes {
                WidgetMetaText("Free \(free) min · \(today.capacityLabel ?? "Steady")")
            }
        }
    }

    private func beatRow(time: String, title: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(time)
                .font(.dsCaption(weight: .bold))
                .foregroundStyle(DesignSystem.focus)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.dsMetadata(weight: .semibold))
                    .foregroundStyle(DesignSystem.textPrimary)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.dsCaption())
                        .foregroundStyle(DesignSystem.textMuted)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var accessibilityCopy: String {
        var parts = ["Today"]
        if let t = today.nextEventTitle, let tm = today.nextEventTimeLabel {
            parts.append("Next event \(tm) \(t)")
        }
        if let task = today.nextTaskTitle {
            parts.append("Next task \(task)")
        }
        if let free = today.freeMinutes {
            parts.append("\(free) free minutes")
        }
        return parts.joined(separator: ". ")
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LookAfterWidgetKind.today, provider: ExecutiveWidgetProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Next event, next task, and free time — nothing else.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
