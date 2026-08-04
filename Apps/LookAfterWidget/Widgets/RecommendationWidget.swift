import WidgetKit
import SwiftUI
import AppIntents
import LookAfterCore

/// P0 — What should I do right now?
struct RecommendationWidgetView: View {
    var entry: ExecutiveWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var rec: WidgetRecommendation { entry.snapshot.resolvedRecommendation }
    private var isClear: Bool {
        rec.title == WidgetRecommendation.clear.title || entry.snapshot.topTaskTitle == nil && entry.snapshot.executive == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetChrome.gap) {
            header
            if isClear {
                WidgetEmptyState(title: "You are clear", detail: "Nothing urgent right now.")
            } else {
                WidgetPrimaryText(rec.title, lineLimit: family == .systemSmall ? 3 : 2)
                if family != .systemSmall, !rec.whyLine.isEmpty {
                    WidgetMetaText(rec.whyLine, lineLimit: 2)
                }
                if family == .systemLarge, let next = rec.nextStepLine, !next.isEmpty {
                    WidgetMetaText(next, lineLimit: 2)
                }
                metaRow
                if family != .systemSmall {
                    actionRow
                }
            }
            if entry.snapshot.isStale {
                WidgetStaleBanner()
            }
            Spacer(minLength: 0)
        }
        .lookAfterWidgetChrome()
        .widgetURL(deepLink)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityCopy)
    }

    private var header: some View {
        HStack {
            WidgetEyebrow("Now", systemImage: "sparkles")
            if !isClear {
                WidgetEnergyChip(
                    score: rec.energyScore ?? entry.snapshot.energyScore,
                    label: family == .systemSmall ? nil : (rec.energyLabel ?? entry.snapshot.energyLevel)
                )
            }
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

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button(intent: CompleteWidgetTaskIntent(taskID: rec.taskID)) {
                Text("Complete")
                    .font(.dsCaption(weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(DesignSystem.accentPrimary))
                    .foregroundStyle(DesignSystem.accentOnPrimary)
            }
            .buttonStyle(.plain)
            Button(intent: SnoozeWidgetTaskIntent(taskID: rec.taskID, minutes: 60)) {
                Text("Snooze 1h")
                    .font(.dsCaption(weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().strokeBorder(DesignSystem.borderPrimary, lineWidth: 1))
                    .foregroundStyle(DesignSystem.textSecondary)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }

    private var deepLink: URL {
        if let id = rec.taskID { return LookAfterDeepLink.task(id: id) }
        return LookAfterDeepLink.recommend
    }

    private var accessibilityCopy: String {
        if isClear { return "No recommended task right now." }
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
