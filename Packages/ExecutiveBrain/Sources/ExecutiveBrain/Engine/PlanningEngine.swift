import Foundation
import LookAfterCore

/// Builds the day plan from world state + reasoning — not a task list poster.
public struct PlanningEngine: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func plan(
        world: WorldState,
        reasoning: ReasoningTrace,
        timelineItems: [LifeTimelineEvent],
        now: Date = Date()
    ) -> DayPlan {
        var blocks: [PlanBlock] = []

        // Medication blocks from configured schedule only
        switch world.medicationStatus {
        case .dueNow(let items), .upcoming(let items):
            for item in items where !item.isTaken {
                blocks.append(PlanBlock(
                    startLabel: item.scheduledTimeLabel,
                    title: item.name,
                    kind: .medication,
                    reasoning: "From your medication schedule"
                ))
            }
        default:
            break
        }

        // Calendar events today
        let calendarEvents = timelineItems
            .filter { $0.kind == .meeting && calendar.isDate($0.date, inSameDayAs: now) && !$0.isCompleted }
            .sorted { $0.date < $1.date }

        for event in calendarEvents.prefix(6) {
            blocks.append(PlanBlock(
                startLabel: event.date.formatted(date: .omitted, time: .shortened),
                title: event.title,
                kind: .meeting,
                reasoning: "On your calendar"
            ))
        }

        // Deep work suggestion when energy allows and window exists
        let shortWindow = world.minutesUntilNextEvent.map { $0 <= 45 } ?? false
        let lowEnergy = world.currentEnergy < 0.45 || world.cognitiveLoad == .overloaded

        if !shortWindow, !lowEnergy, let mission = world.currentMission {
            let profile = mission.resolvedSemanticProfile
            if profile.semanticType != .medication,
               TaskSemanticScheduler.isDeepWorkCandidate(profile: profile) || profile.cognitiveRequirement == .moderate {
                let deepWorkHour = preferredHour(for: profile, now: now, calendar: calendar)
                blocks.append(PlanBlock(
                    startLabel: String(format: "%02d:00", deepWorkHour),
                    title: mission.title,
                    kind: .deepWork,
                    reasoning: profile.requiredConditions.first ?? reasoning.conclusions.first
                ))
            }
        } else if lowEnergy {
            blocks.append(PlanBlock(
                startLabel: "Now",
                title: "Eat and recover",
                kind: .meal,
                reasoning: "Energy is low — food and rest come first"
            ))
        }

        let summary = reasoning.conclusions.prefix(2).joined(separator: " ")

        return DayPlan(
            blocks: blocks.sorted { $0.startLabel < $1.startLabel },
            narrativeSummary: summary,
            generatedAt: now
        )
    }

    private func preferredHour(for profile: TaskSemanticProfile, now: Date, calendar: Calendar) -> Int {
        let lifeProfile = UserLifeProfileStore.load()
        let currentHour = calendar.component(.hour, from: now)
        if profile.preferredTimeWindows.contains(.morning) {
            return max(currentHour, lifeProfile.peakStartHour)
        }
        if profile.preferredTimeWindows.contains(.evening) {
            return max(currentHour + 2, max(lifeProfile.workEndHour - 2, lifeProfile.peakEndHour + 1))
        }
        return max(currentHour + 1, lifeProfile.peakStartHour)
    }
}
