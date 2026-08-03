import Foundation
import LookAfterCore

/// AI-powered task detail auto-fill from a title using GLM.
public final class TaskAutoFiller: @unchecked Sendable {
    
    private let glm: GLMService

    public init(glmService: GLMService = .shared) {
        self.glm = glmService
    }
    
    /// Infer task details from a title.
    public func fill(title: String) async throws -> TaskAutoFillResult {
        let prompt = LookAfterPrompts.taskAutoFillPrompt(title: title)
        let response = try await glm.complete(
            prompt: prompt,
            systemPrompt: LookAfterPrompts.structuredOutputSystem,
            tier: .economy
        )
        
        let cleaned = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleaned.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TaskAutoFillerError.parseError
        }
        
        let description = json["description"] as? String ?? ""
        let estimatedMinutes = json["estimatedMinutes"] as? Int ?? TaskDurationPolicy.defaultMinutes
        
        let lifeAreaStr = json["lifeArea"] as? String ?? "Personal"
        let lifeArea = LifeArea.allCases.first { $0.rawValue == lifeAreaStr } ?? .personal
        
        let priorityStr = json["priority"] as? String ?? "Medium"
        let priority = Priority.allCases.first { $0.label == priorityStr } ?? .medium
        
        let difficultyStr = json["difficulty"] as? String ?? "Medium"
        let difficulty = TaskDifficulty.allCases.first { $0.rawValue == difficultyStr } ?? .medium
        
        let recurrenceStr = json["recurrence"] as? String ?? "Does not repeat"
        let recurrence = TaskRecurrence.allCases.first { $0.rawValue == recurrenceStr } ?? .none
        
        return TaskAutoFillResult(
            description: description,
            lifeArea: lifeArea,
            priority: priority,
            difficulty: difficulty,
            estimatedMinutes: TaskDurationPolicy.clamp(estimatedMinutes, allowShortTasks: true),
            recurrence: recurrence
        )
    }
}

public struct TaskAutoFillResult: Sendable {
    public var description: String
    public var lifeArea: LifeArea
    public var priority: Priority
    public var difficulty: TaskDifficulty
    public var estimatedMinutes: Int
    public var recurrence: TaskRecurrence
}

public enum TaskAutoFillerError: Error, LocalizedError {
    case parseError
    
    public var errorDescription: String? {
        switch self {
        case .parseError: return "Could not parse AI response"
        }
    }
}
