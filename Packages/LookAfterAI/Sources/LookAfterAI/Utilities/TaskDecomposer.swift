import Foundation
import LookAfterCore

/// Decomposes complex tasks into 5-minute actionable micro-steps using GLM.
public final class TaskDecomposer: @unchecked Sendable {
    private let glm: GLMService

    public init(glmService: GLMService = .shared) {
        self.glm = glmService
    }

    public func decompose(task: LifeTask) async throws -> (steps: [TaskStep], recurrence: TaskRecurrence) {
        let prompt = LookAfterPrompts.taskDecompositionPrompt(task: task)
        let response = try await glm.complete(
            prompt: prompt,
            systemPrompt: LookAfterPrompts.structuredOutputSystem
        )

        let cleaned = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw DecomposerError.parseError("Failed to convert response to data")
        }

        struct Response: Decodable {
            var detectedRecurrence: String?
            var steps: [StepDTO]?
        }
        struct StepDTO: Decodable {
            var title: String
            var estimatedMinutes: Int?
        }

        if let parsed = try? JSONDecoder().decode(Response.self, from: data),
           let steps = parsed.steps, !steps.isEmpty {
            let taskSteps = steps.map {
                TaskStep(
                    title: $0.title,
                    estimatedMinutes: TaskDurationPolicy.clamp($0.estimatedMinutes ?? TaskDurationPolicy.softDefaultMinutes, allowShortTasks: true)
                )
            }
            let recurrence = Self.parseRecurrence(parsed.detectedRecurrence)
            return (taskSteps, recurrence)
        }

        return ([TaskStep(title: "Start working on: \(task.title)", estimatedMinutes: max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes))], .none)
    }

    private static func parseRecurrence(_ raw: String?) -> TaskRecurrence {
        guard let raw, !raw.isEmpty else { return .none }
        if let exact = TaskRecurrence(rawValue: raw) { return exact }
        switch raw.lowercased() {
        case "daily", "every day": return .daily
        case "weekly", "every week": return .weekly
        case "weekdays": return .weekdays
        case "weekends": return .weekends
        case "monthly", "every month": return .monthly
        case "yearly", "every year": return .yearly
        case "none", "does not repeat": return .none
        default: return .none
        }
    }
}

public enum DecomposerError: Error, LocalizedError {
    case parseError(String)
    public var errorDescription: String? {
        switch self {
        case .parseError(let msg): return msg
        }
    }
}
