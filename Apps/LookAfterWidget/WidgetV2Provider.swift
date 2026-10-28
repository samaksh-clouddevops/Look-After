import WidgetKit
import SwiftUI
import LookAfterCore

// MARK: - Entry

struct ExecutiveWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - Extension-only chrome (WidgetKit must not live in LookAfterCore)

extension View {
    /// Standard V2 widget root: padding + system widget background.
    func lookAfterWidgetChrome() -> some View {
        WidgetRootPadding {
            self
        }
        .containerBackground(for: .widget) {
            WidgetChrome.canvasBackground()
        }
    }
}

// MARK: - Shared App Group load (matches main-app store key)

enum WidgetSnapshotStore {
    static func load() -> WidgetSnapshot {
        guard
            let defaults = UserDefaults(suiteName: WidgetAppGroup.identifier),
            let data = defaults.data(forKey: WidgetAppGroup.snapshotKey),
            let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else {
            return .empty
        }
        return snapshot
    }
}

// MARK: - Provider

struct ExecutiveWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ExecutiveWidgetEntry {
        ExecutiveWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ExecutiveWidgetEntry) -> Void) {
        completion(ExecutiveWidgetEntry(date: Date(), snapshot: WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ExecutiveWidgetEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.load()
        let entry = ExecutiveWidgetEntry(date: Date(), snapshot: snapshot)
        let next = Calendar.current.date(byAdding: .minute, value: 20, to: Date()) ?? Date().addingTimeInterval(1200)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Placeholder sample (no PII)

extension WidgetSnapshot {
    static var placeholder: WidgetSnapshot {
        WidgetSnapshot(
            topTaskTitle: "Review project notes",
            topTaskMinutes: 25,
            energyScore: 72,
            energyLevel: "High",
            recommendation: "Open window before your next meeting.",
            completedTodayCount: 2,
            activeTaskCount: 4,
            sleepHours: 7.2,
            stepCount: 3200,
            hrvMs: 48,
            tasks: [
                WidgetTaskItem(id: "1", title: "Review project notes", estimatedMinutes: 25, priorityLabel: "High"),
                WidgetTaskItem(id: "2", title: "Reply to messages", estimatedMinutes: 15, priorityLabel: "Medium")
            ],
            executive: WidgetRecommendation(
                taskID: "1",
                title: "Review project notes",
                whyLine: "Open window before your next meeting.",
                nextStepLine: "Start with the outline section.",
                estimatedMinutes: 25,
                energyLabel: "High",
                energyScore: 72
            ),
            today: WidgetTodaySummary(
                nextEventTitle: "Standup",
                nextEventTimeLabel: "10:30",
                nextTaskTitle: "Review project notes",
                freeMinutes: 48,
                capacityLabel: "Steady",
                beats: [
                    WidgetTimelineBeat(id: "e1", timeLabel: "10:30", title: "Standup", detail: "15m", kind: "meeting"),
                    WidgetTimelineBeat(id: "t1", timeLabel: "Next", title: "Review notes", detail: "25m", kind: "task")
                ]
            ),
            focus: .idle,
            medication: WidgetMedicationStatus(
                id: "m1",
                name: "Morning dose",
                timeLabel: "8:00 AM",
                isTaken: false,
                dosage: ""
            ),
            recoveryLabel: "Good recovery",
            schemaVersion: 2
        )
    }
}
