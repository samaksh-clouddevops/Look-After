import Foundation
import LifeOSCore

/// Multi-factor reasoning — the Brain thinks, the LLM explains.
public struct ReasoningEngine: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func reason(over world: WorldState, now: Date = Date()) -> ReasoningTrace {
        var factors: [ReasoningFactor] = []
        factors.append(contentsOf: sleepFactors(world))
        factors.append(contentsOf: energyFactors(world))
        factors.append(contentsOf: calendarFactors(world))
        factors.append(contentsOf: MedicationReasoningEngine.reasoningFactors(for: world.medicationStatus))
        factors.append(contentsOf: deadlineFactors(world, now: now))
        factors.append(contentsOf: flowFactors(world))

        let conclusions = deriveConclusions(from: factors, world: world)

        return ReasoningTrace(factors: factors, conclusions: conclusions, generatedAt: now)
    }

    // MARK: - Factor builders

    private func sleepFactors(_ world: WorldState) -> [ReasoningFactor] {
        guard let hours = world.sleepHoursLastNight else { return [] }
        if hours < 6 {
            return [
                ReasoningFactor(
                    domain: .sleep,
                    observation: "Sleep was \(formatHours(hours)) — below recovery threshold.",
                    impact: .opposes,
                    weight: 0.9
                )
            ]
        }
        if world.sleepQuality == .good || world.sleepQuality == .excellent {
            return [
                ReasoningFactor(
                    domain: .sleep,
                    observation: "Sleep was solid last night.",
                    impact: .supports,
                    weight: 0.6
                )
            ]
        }
        return []
    }

    private func energyFactors(_ world: WorldState) -> [ReasoningFactor] {
        if world.currentEnergy < 0.45 {
            return [
                ReasoningFactor(
                    domain: .energy,
                    observation: "Energy is low right now.",
                    impact: .opposes,
                    weight: 0.75
                )
            ]
        }
        if world.currentEnergy >= 0.7 {
            return [
                ReasoningFactor(
                    domain: .energy,
                    observation: "Energy is good for your top priority.",
                    impact: .supports,
                    weight: 0.65
                )
            ]
        }
        return []
    }

    private func calendarFactors(_ world: WorldState) -> [ReasoningFactor] {
        guard let mins = world.minutesUntilNextEvent, let event = world.nextEventTitle else { return [] }
        if mins <= 45 {
            return [
                ReasoningFactor(
                    domain: .calendar,
                    observation: "\(event) starts in \(mins) minutes — not enough time for a long block.",
                    impact: .constrains,
                    weight: 0.85
                )
            ]
        }
        if mins <= 120 {
            return [
                ReasoningFactor(
                    domain: .calendar,
                    observation: "\(mins) minutes until \(event).",
                    impact: .constrains,
                    weight: 0.55
                )
            ]
        }
        return []
    }

    private func deadlineFactors(_ world: WorldState, now: Date) -> [ReasoningFactor] {
        guard let nearest = world.upcomingDeadlines.first else { return [] }
        switch nearest.daysRemaining {
        case ..<0:
            return [
                ReasoningFactor(
                    domain: .tasks,
                    observation: "\(nearest.taskTitle) is overdue.",
                    impact: .constrains,
                    weight: 0.8
                )
            ]
        case 0:
            return [
                ReasoningFactor(
                    domain: .tasks,
                    observation: "\(nearest.taskTitle) is due today.",
                    impact: .constrains,
                    weight: 0.75
                )
            ]
        case 1:
            return [
                ReasoningFactor(
                    domain: .tasks,
                    observation: "\(nearest.taskTitle) is due tomorrow.",
                    impact: .constrains,
                    weight: 0.55
                )
            ]
        default:
            return []
        }
    }

    private func flowFactors(_ world: WorldState) -> [ReasoningFactor] {
        if world.isInFlowSession {
            return [
                ReasoningFactor(
                    domain: .focus,
                    observation: "You're already mid-task — switching now costs momentum.",
                    impact: .supports,
                    weight: 0.9
                )
            ]
        }
        if world.cognitiveLoad == .overloaded {
            return [
                ReasoningFactor(
                    domain: .energy,
                    observation: "Cognitive load is high — keep the next step small.",
                    impact: .opposes,
                    weight: 0.8
                )
            ]
        }
        return []
    }

    // MARK: - Conclusions

    private func deriveConclusions(from factors: [ReasoningFactor], world: WorldState) -> [String] {
        var conclusions: [String] = []

        let poorSleep = factors.contains { $0.domain == .sleep && $0.impact == .opposes }
        let lowEnergy = factors.contains { $0.domain == .energy && $0.impact == .opposes }
        let shortWindow = factors.contains { $0.domain == .calendar && $0.impact == .constrains && ($0.observation.contains("45 minutes") || $0.observation.contains("not enough")) }
        let medicationDue = factors.contains { $0.domain == .medication && $0.impact == .constrains }
        let inFlow = factors.contains { $0.domain == .focus && $0.impact == .supports }
        let deadlineTomorrow = world.upcomingDeadlines.contains { $0.daysRemaining == 1 }

        if inFlow {
            conclusions.append("Continue where you are — switching now costs momentum.")
        }

        if poorSleep || lowEnergy {
            conclusions.append("Keep the next step small for now.")
        }

        if shortWindow {
            conclusions.append("Use this window for something light or preparatory.")
        }

        if medicationDue, let message = MedicationReasoningEngine.reminderMessage(for: world.medicationStatus) {
            conclusions.append(message)
        }

        if (poorSleep || lowEnergy) && deadlineTomorrow && !shortWindow {
            conclusions.append("A short focused block now still helps — finish the rest later.")
        }

        if conclusions.isEmpty {
            conclusions.append("This is a reasonable moment for your top priority.")
        }

        return conclusions
    }

    private func formatHours(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }
}
