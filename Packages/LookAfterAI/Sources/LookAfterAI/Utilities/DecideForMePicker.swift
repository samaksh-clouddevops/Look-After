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
        tasks: [LifeTask]
    ) async -> DecideForMeResult? {
        let openWindow = max(15, Int((1.0 - snapshot.energyScore) * 30) + 45)
        let energyPercent = Int(snapshot.energyScore * 100)
        let feasible = DaySupervisorContinuity.feasibleTasks(
            from: tasks,
            openWindowMinutes: openWindow,
            energyPercent: energyPercent
        )
        let candidates = feasible.isEmpty ? tasks.filter(\.status.isActive) : feasible
        guard !candidates.isEmpty else { return nil }

        let prompt = LookAfterPrompts.decideForMePrompt(snapshot: snapshot, tasks: candidates)
        do {
            let raw = try await glm.complete(
                prompt: prompt,
                systemPrompt: LookAfterPrompts.structuredOutputSystem,
                tier: .economy
            )
            if let parsed = parseResponse(raw, candidates: candidates) {
                return parsed
            }
        } catch {
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
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = json["selectedTaskTitle"] as? String else {
            return nil
        }
        let reason = (json["reason"] as? String) ?? "This feels like the most approachable next step right now."
        guard let task = candidates.first(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame })
            ?? candidates.first(where: { $0.title.localizedCaseInsensitiveContains(title) || title.localizedCaseInsensitiveContains($0.title) })
            ?? candidates.first else {
            return nil
        }
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
                return $0.estimatedMinutes <= $1.estimatedMinutes
            }
        }
        let task = sorted[0]
        return DecideForMeResult(
            task: task,
            reason: "Starting with something manageable that still moves your day forward."
        )
    }
}
