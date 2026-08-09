import Foundation
import LookAfterAI
import LookAfterCore

/// Builds small sectional insights for the briefing footer from module data.
enum BriefingModuleInsightsBuilder {

    struct Input: Sendable {
        var userName: String
        var progress: BriefingProgressData
        var mission: BriefingMissionData
        var sleep: BriefingSleepData
        var energy: BriefingEnergyData
        var executiveCapacity: ExecutiveCapacityState
        var habits: [BriefingHabit]
        var calendar: BriefingCalendarData
        var lifeGaps: [LifeGap]
        var proactiveSuggestions: [ScheduleProactiveSuggestion]
        var cycleData: BriefingCycleData
        var alerts: [BriefingAlert]
        var aiRecommendation: String?
    }

    static func buildDeterministic(_ input: Input) -> [BriefingModuleInsight] {
        var insights: [BriefingModuleInsight] = []

        if input.progress.remainingCount > 0 {
            var message = "You’ve got \(input.progress.remainingCount) task\(input.progress.remainingCount == 1 ? "" : "s") left today."
            if input.progress.overdueCount > 0 {
                message += " \(input.progress.overdueCount) could use a quick decision so they stop nagging you."
            } else if input.mission.completionPercent > 0 {
                message += " Nice — \(input.mission.completionPercent)% already done."
            }
            insights.append(BriefingModuleInsight(module: "Tasks", icon: "checklist", message: message))
        } else if input.progress.completedCount > 0 {
            insights.append(BriefingModuleInsight(
                module: "Tasks",
                icon: "checklist",
                message: "Today’s list is clear. Capture anything still on your mind before it becomes background noise."
            ))
        }

        if input.sleep.isAvailable, let hours = input.sleep.totalHours {
            let sleepMessage: String
            if hours < 6 {
                sleepMessage = String(format: "Sleep was short at %.1f hours — keep the first block light and protect a real break.", hours)
            } else if hours >= 7.5 {
                sleepMessage = String(format: "Sleep landed around %.1f hours. Your brain has room for one meaningful push.", hours)
            } else {
                sleepMessage = String(format: "About %.1f hours of sleep — steady enough for admin, save heavy thinking for your peak window.", hours)
            }
            insights.append(BriefingModuleInsight(module: "Health", icon: "bed.double.fill", message: sleepMessage))
        } else if input.energy.currentEnergyPercent > 0 {
            insights.append(BriefingModuleInsight(
                module: "Energy",
                icon: "bolt.fill",
                message: "Energy’s around \(input.energy.currentEnergyPercent)% — \(input.executiveCapacity.band.tagline.lowercased())"
            ))
        }

        let pendingHabits = input.habits.filter { !$0.isCompletedToday }
        if !pendingHabits.isEmpty {
            let names = pendingHabits.prefix(2).map(\.title).joined(separator: ", ")
            insights.append(BriefingModuleInsight(
                module: "Habits",
                icon: "leaf.fill",
                message: "Still open: \(names). Even a two-minute version counts."
            ))
        }

        if let gap = input.lifeGaps.first {
            insights.append(BriefingModuleInsight(
                module: "Life areas",
                icon: "sparkles",
                message: gap.message
            ))
        }

        if let suggestion = input.proactiveSuggestions.first {
            insights.insert(
                BriefingModuleInsight(
                    module: "Schedule",
                    icon: "exclamationmark.bubble.fill",
                    message: suggestion.message
                ),
                at: 0
            )
        }

        if input.cycleData.isVisible, let insight = input.cycleData.topInsight {
            insights.append(BriefingModuleInsight(
                module: "Cycle",
                icon: "circle.circle.fill",
                message: insight.body
            ))
        }

        if let title = input.calendar.nextEventTitle, let minutes = input.calendar.minutesUntilStart {
            let when = minutes <= 60 ? "in \(minutes) min" : "later today"
            insights.append(BriefingModuleInsight(
                module: "Schedule",
                icon: "calendar",
                message: "Next up: \(title) \(when)."
            ))
        }

        if let recommendation = input.aiRecommendation, !recommendation.isEmpty, insights.count < 3 {
            insights.append(BriefingModuleInsight(
                module: "Brain",
                icon: "brain.head.profile",
                message: UserFacingCopy.sanitize(recommendation)
            ))
        }

        if insights.isEmpty, let alert = input.alerts.first {
            insights.append(BriefingModuleInsight(
                module: "Today",
                icon: alert.icon,
                message: alert.message
            ))
        }

        return Array(insights.prefix(4))
    }

    static func supplementWithAI(
        existing: [BriefingModuleInsight],
        input: Input
    ) async -> [BriefingModuleInsight] {
        guard existing.count < 2 else { return existing }

        let hasKey = GLMService.shared.hasConfiguredAPIKey
        guard hasKey else {
            return existing + fallbackSuggestions(input: input, excluding: existing)
        }

        let name = input.userName.isEmpty ? "there" : input.userName
        let prompt = """
        User: \(name)
        Tasks remaining: \(input.progress.remainingCount)
        Completed today: \(input.progress.completedCount)
        Energy: \(input.energy.currentEnergyPercent)%
        Capacity: \(input.executiveCapacity.band.displayLabel)
        Sleep available: \(input.sleep.isAvailable)
        Habits pending: \(input.habits.count)
        Life gaps: \(input.lifeGaps.count)

        Write 2-3 short, warm briefing insights (one sentence each) for an ADHD user.
        Cover different life areas (tasks, health, habits, relationships, rest) when possible.
        No bullet characters. Return JSON array: [{"module":"Tasks","icon":"checklist","message":"..."}]
        """

        do {
            let raw = try await GLMService.shared.complete(
                prompt: prompt,
                systemPrompt: LookAfterPrompts.briefingModuleInsightsSystem,
                tier: .economy
            )
            let parsed = parseAIInsights(raw)
            if parsed.isEmpty {
                return existing + fallbackSuggestions(input: input, excluding: existing)
            }
            var merged = existing
            for insight in parsed where merged.count < 4 {
                guard !merged.contains(where: { $0.message == insight.message }) else { continue }
                merged.append(insight)
            }
            return merged
        } catch {
            return existing + fallbackSuggestions(input: input, excluding: existing)
        }
    }

    private static func fallbackSuggestions(input: Input, excluding: [BriefingModuleInsight]) -> [BriefingModuleInsight] {
        let options: [BriefingModuleInsight] = [
            BriefingModuleInsight(
                module: "Today",
                icon: "sun.max.fill",
                message: "Pick one small win for the next hour — momentum beats a perfect plan."
            ),
            BriefingModuleInsight(
                module: "Focus",
                icon: "scope",
                message: "Your peak window is a good time for the task you've been avoiding."
            ),
            BriefingModuleInsight(
                module: "Rest",
                icon: "cup.and.saucer.fill",
                message: "A five-minute reset now can save you from an afternoon crash."
            ),
            BriefingModuleInsight(
                module: "Capture",
                icon: "tray.full",
                message: "Anything still circling in your head? Jot it down so your brain can let go."
            )
        ]
        return options.filter { candidate in
            !excluding.contains(where: { $0.message == candidate.message })
        }.prefix(max(0, 3 - excluding.count)).map { $0 }
    }

    private static func parseAIInsights(_ raw: String) -> [BriefingModuleInsight] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonSlice: String
        if let start = trimmed.firstIndex(of: "["), let end = trimmed.lastIndex(of: "]") {
            jsonSlice = String(trimmed[start...end])
        } else {
            return []
        }
        guard let data = jsonSlice.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array.compactMap { object in
            guard let message = (object["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !message.isEmpty else { return nil }
            let module = (object["module"] as? String) ?? "Today"
            let icon = SystemImage.resolved(object["icon"] as? String, fallback: "sparkles")
            return BriefingModuleInsight(module: module, icon: icon, message: UserFacingCopy.sanitize(message))
        }
    }
}
