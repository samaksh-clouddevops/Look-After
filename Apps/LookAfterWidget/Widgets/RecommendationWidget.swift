import WidgetKit
import SwiftUI
import LookAfterCore

/// P0 — What should I do right now?
struct RecommendationWidgetView: View {
    var entry: ExecutiveWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var rec: WidgetRecommendation { entry.snapshot.resolvedRecommendation }

    var body: some View {
        WidgetRootContainer {
            VStack(alignment: .leading, spacing: WidgetChrome.gap) {
                header
                WidgetPrimaryText(rec.title, lineLimit: family == .systemSmall ? 3 : 2)
                if family != .systemSmall, !rec.whyLine.isEmpty {
                    WidgetMetaText(rec.whyLine, lineLimit: 2)
                }
                if family == .systemLarge, let next = rec.nextStepLine, !next.isEmpty {
                    WidgetMetaText(next, lineLimit: 2)
                }
                metaRow
                if entry.snapshot.isStale {
                    WidgetStaleBanner()
                }
                Spacer(minLength: 0)
            }
        }
        .widgetURL(deepLink)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityCopy)
    }

    private var header: some View {
        HStack {
            WidgetEyebrow("Now", systemImage: "sparkles")
            WidgetEnergyChip(
                score: rec.energyScore ?? entry.snapshot.energyScore,
                label: family == .systemSmall ? nil : (rec.energyLabel ?? entry.snapshot.energyLevel)
            )
        }
    }

    @ViewBuilder
    private var metaRow: some View {
        if let mins = rec.estimatedMinutes {
            Text("~\(mins) min")
                .font(.dsMetadata())
                .foregroundStyle(DesignSystem.textMuted)
        } else if family == .systemSmall {
            Text("\(entry.snapshot.completedTodayCount) done today")
                .font(.dsMetadata())
                .foregroundStyle(DesignSystem.textMuted)
        }
    }

    private var deepLink: URL {
        if let id = rec.taskID { return LookAfterDeepLink.task(id: id) }
        return LookAfterDeepLink.recommend
    }

    private var accessibilityCopy: String {
        var parts = ["Next step: \(rec.title)"]
        if let m = rec.estimatedMinutes { parts.append("about \(m) minutes") }
        if !rec.whyLine.isEmpty { parts.append(rec.whyLine) }
        return parts.joined(separator: ". ")
    }
}

struct RecommendationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LookAfterWidgetKind.recommendation, provider: ExecutiveWidgetProvider()) { entry in
            RecommendationWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Step")
        .description("Your Executive Brain recommendation — what matters right now.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
