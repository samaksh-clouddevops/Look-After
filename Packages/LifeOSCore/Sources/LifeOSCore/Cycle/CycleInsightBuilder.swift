import Foundation

public enum CycleInsightBuilder {

    public static func build(
        snapshot: CycleSnapshot,
        logs: [CycleDayLog],
        sleepHours: Double? = nil,
        hrv: Int? = nil,
        calendar: Calendar = .current
    ) -> [CycleInsight] {
        guard snapshot.isEnabled else { return [] }

        var insights: [CycleInsight] = []

        if snapshot.confidence == .low {
            insights.append(
                CycleInsight(
                    headline: "Still learning your cycle",
                    body: "Log your period start and how you feel over the next couple of cycles — insights get much more useful after that.",
                    actionKind: .logSymptom,
                    priority: 10
                )
            )
        }

        if let days = snapshot.daysUntilPeriod, days <= 2, days > 0 {
            insights.append(
                CycleInsight(
                    headline: "Period approaching",
                    body: "Protect the next couple of days — lighter plan, earlier wind-down, and keep hard focus blocks short.",
                    actionKind: .adjustPlan,
                    priority: 90
                )
            )
        }

        if snapshot.phase == .menstrual, let day = snapshot.cycleDay, day <= 2 {
            var body = "Recovery mode — defer demanding work if you can and batch admin or low-energy tasks."
            if let sleep = sleepHours, sleep < 6.5 {
                body += " Sleep was short last night, so protect rest even more today."
            }
            insights.append(
                CycleInsight(
                    headline: "Menstrual phase · take it easier",
                    body: body,
                    actionKind: .recoveryMode,
                    priority: 95
                )
            )
        }

        if snapshot.phase == .luteal {
            let lutealLogs = logs.filter { log in
                let snap = CycleEngine.snapshot(
                    CycleEngine.Input(
                        preferences: CyclePreferencesStore.load(),
                        logs: logs,
                        now: log.day,
                        calendar: calendar
                    )
                )
                return snap.phase == .luteal
            }
            let lowEnergyCount = lutealLogs.filter { ($0.energy ?? 5) <= 2 }.count
            if lowEnergyCount >= 2 {
                insights.append(
                    CycleInsight(
                        headline: "Luteal phase pattern",
                        body: "You've logged lower energy in this phase before — schedule deep work for mornings and keep afternoons lighter.",
                        actionKind: .protectEnergy,
                        priority: 80
                    )
                )
            }
        }

        let symptomPatterns = CycleEngine.symptomFrequencyByPhase(
            input: CycleEngine.Input(logs: logs, calendar: calendar)
        )
        if let phaseSymptoms = symptomPatterns[snapshot.phase], let top = phaseSymptoms.max(by: { $0.value < $1.value }), top.value >= 2 {
            insights.append(
                CycleInsight(
                    headline: "\(top.key) often shows up now",
                    body: "You've logged \(top.key.lowercased()) during \(snapshot.phase.displayLabel.lowercased()) phase \(top.value) times — plan buffer and self-care around it.",
                    actionKind: .logSymptom,
                    priority: 70
                )
            )
        }

        if let hrv, hrv < 35, snapshot.phase == .luteal || snapshot.phase == .menstrual {
            insights.append(
                CycleInsight(
                    headline: "Recovery signal",
                    body: "HRV is lower than usual during \(snapshot.phase.displayLabel.lowercased()) phase — favor rest and avoid stacking meetings.",
                    actionKind: .protectEnergy,
                    priority: 75
                )
            )
        }

        return insights.sorted { $0.priority > $1.priority }
    }

    public static func capacityModifier(snapshot: CycleSnapshot, logs: [CycleDayLog], calendar: Calendar = .current) -> Int {
        guard snapshot.isEnabled else { return 0 }
        switch snapshot.phase {
        case .menstrual:
            return snapshot.cycleDay.map { $0 <= 2 ? -12 : -8 } ?? -8
        case .luteal:
            let lutealLogs = logs.filter {
                CycleEngine.snapshot(
                    CycleEngine.Input(
                        preferences: CyclePreferencesStore.load(),
                        logs: logs,
                        now: $0.day,
                        calendar: calendar
                    )
                ).phase == .luteal
            }
            let lowEnergy = lutealLogs.filter { ($0.energy ?? 5) <= 2 }.count
            return lowEnergy >= 2 ? -8 : -4
        case .ovulation:
            return 2
        case .follicular:
            return 4
        case .unknown:
            return 0
        }
    }
}
