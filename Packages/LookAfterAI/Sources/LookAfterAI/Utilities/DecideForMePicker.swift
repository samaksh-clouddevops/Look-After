import Foundation
import LookAfterCore

public struct DecideForMeResult: Sendable, Equatable {
    public var task: LifeTask
    public var reason: String

    public init(task: LifeTask, reason: String) {
        self.task = task
        self.reason = reason
    }
}

/// Picks a single task for zero-choice overwhelm mode using LLM + deterministic fallback.
public final class DecideForMePicker: @unchecked Sendable {
    private let glm: GLMService

    public init(glmService: GLMService = .shared) {
        self.glm = glmService
    }

    public func pick(
        snapshot: CognitiveSnapshot,
        tasks: [LifeTask],
        referenceDate: Date = Date()
    ) async -> DecideForMeResult? {
        guard !Task.isCancelled else { return nil }
        let actionable = tasks.filter {
            $0.status.isActive && $0.isActionableToday(allTasks: tasks, referenceDate: referenceDate)
        }
        let openWindow = max(15, Int((1.0 - snapshot.energyScore) * 30) + 45)
        let energyPercent = Int(snapshot.energyScore * 100)
        let feasible = DaySupervisorContinuity.feasibleTasks(
            from: actionable,
            openWindowMinutes: openWindow,
            energyPercent: energyPercent
        )
        let candidates = feasible.isEmpty ? actionable : feasible
        guard !candidates.isEmpty else { return nil }

        let prompt = LookAfterPrompts.decideForMePrompt(snapshot: snapshot, tasks: candidates)
        do {
            let raw = try await glm.complete(
                prompt: prompt,
                systemPrompt: LookAfterPrompts.structuredOutputSystem,
                tier: .economy
            )
            guard !Task.isCancelled else { return nil }
            if let parsed = parseResponse(raw, candidates: candidates) {
                return parsed
            }
        } catch {
            guard !Task.isCancelled else { return nil }
            print("[DecideForMe] AI unavailable: \(error.localizedDescription)")
        }
        return deterministicFallback(snapshot: snapshot, candidates: candidates)
    }

    private func parseResponse(_ raw: String, candidates: [LifeTask]) -> DecideForMeResult? {
        let clean = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = clean.firstIndex(of: "{"), let end = clean.lastIndex(of: "}"),
              let data = String(clean[start...end]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let task: LifeTask
        if let id = json["selectedTaskID"] as? String {
            guard let match = candidates.first(where: { $0.id == id }) else { return nil }
            task = match
        } else if let title = json["selectedTaskTitle"] as? String {
            let matches = candidates.filter { $0.title.caseInsensitiveCompare(title) == .orderedSame }
            guard matches.count == 1, let match = matches.first else { return nil }
            task = match
        } else {
            return nil
        }
        let explanation = (json["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = explanation.flatMap { $0.isEmpty ? nil : $0 }
            ?? "This feels like the most approachable next step right now."
        return DecideForMeResult(task: task, reason: reason)
    }

    private func deterministicFallback(snapshot: CognitiveSnapshot, candidates: [LifeTask]) -> DecideForMeResult {
        let sorted: [LifeTask]
        if snapshot.energyScore < 0.4 {
            sorted = candidates.sorted {
                if $0.estimatedMinutes != $1.estimatedMinutes { return $0.estimatedMinutes < $1.estimatedMinutes }
                return $0.priority > $1.priority
            }
        } else {
            sorted = candidates.sorted {
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                if $0.estimatedMinutes != $1.estimatedMinutes { return $0.estimatedMinutes < $1.estimatedMinutes }
                return $0.id < $1.id
            }
        }
        let task = sorted[0]
        return DecideForMeResult(
            task: task,
            reason: "Starting with something manageable that still moves your day forward."
        )
    }
}
