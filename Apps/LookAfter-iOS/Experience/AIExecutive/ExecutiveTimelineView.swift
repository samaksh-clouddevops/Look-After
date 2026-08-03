import SwiftUI
import LookAfterCore
import LookAfterFeatures

/// Unified chronological timeline across all modules.
struct ExecutiveTimelineView: View {
    @EnvironmentObject private var shell: AppShellState

    let userId: String

    private var items: [LifeTimelineEvent] {
        shell.contextOrchestrator.lifeTimelineEvents
    }

    var body: some View {
        ZStack {
            PremiumBackground()

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Timeline")
                            .font(.dsLargeTitle())
                            .foregroundColor(DesignSystem.textPrimary)
                        Text("Everything in one place")
                            .font(.dsCaption())
                            .foregroundColor(DesignSystem.textMuted)
                    }
                    Spacer()
                }
                .padding(DesignSystem.spacingMD)

                if items.isEmpty {
                    Spacer()
                    VStack(spacing: DesignSystem.spacingSM) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 40))
                            .foregroundColor(DesignSystem.textMuted)
                        Text("Your timeline fills as you add tasks, bills, and events.")
                            .font(.dsBody())
                            .foregroundColor(DesignSystem.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(groupedByDay, id: \.title) { section in
                            Section {
                                ForEach(section.items) { item in
                                    timelineRow(item)
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                }
                            } header: {
                                Text(section.title)
                                    .font(.dsCaption(weight: .bold))
                                    .foregroundColor(DesignSystem.textMuted)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable {
                        await reloadTimeline(userId: userId)
                    }
                }
            }
        }
        .task {
            await reloadTimeline(userId: userId)
        }
        .accessibilityIdentifier("screen-executive-timeline")
    }

    private func reloadTimeline(userId: String) async {
        await shell.tasksVM.loadTasks(userId: userId)
        let name = UserLifeProfileStore.resolvedDisplayName()
        let peak = UserLifeProfileStore.load().peakStartHour
        await shell.refreshContext(userId: userId, userName: name, peakStartHour: peak)
        await shell.modulesVM.loadAllData(userId: userId)
    }

    private var groupedByDay: [(title: String, items: [LifeTimelineEvent])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: items) { item in
            calendar.startOfDay(for: item.date)
        }
        return grouped.keys.sorted().map { day in
            let label = calendar.isDateInToday(day) ? "Today" : day.formatted(date: .abbreviated, time: .omitted)
            let dayItems = grouped[day]?.sorted { $0.date < $1.date } ?? []
            return (label, dayItems)
        }
    }

    private func timelineRow(_ item: LifeTimelineEvent) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.spacingSM) {
            Image(systemName: item.kind.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(DesignSystem.accentPrimary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.dsBody(weight: .semibold))
                    .foregroundColor(item.isCompleted ? DesignSystem.textMuted : DesignSystem.textPrimary)
                    .strikethrough(item.isCompleted)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.dsCaption())
                        .foregroundColor(DesignSystem.textMuted)
                }
            }

            Spacer()

            Text(item.date.formatted(date: .omitted, time: .shortened))
                .font(.dsCaption())
                .foregroundColor(DesignSystem.textSecondary)
        }
        .padding(.vertical, DesignSystem.spacingXS)
        .elevatedSurface(padding: DesignSystem.spacingSM, cornerRadius: DesignSystem.radiusMD)
    }
}
