import Foundation
import LookAfterCore

/// Reads import files and uses GLM to extract structured tasks.
public final class TaskImporter: @unchecked Sendable {

    private let glm: GLMService
    private let maxTextCharacters = 40_000

    public init(glmService: GLMService = .shared) {
        self.glm = glmService
    }
    
    /// Parse tasks from raw file data.
    public func importTasks(from data: Data, fileName: String) async throws -> TaskImportResult {
        let ext = (fileName as NSString).pathExtension.lowercased()
        
        switch ext {
        case "txt", "csv", "tsv", "md":
            guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                throw TaskImportError.emptyFile
            }
            return try await parseTextImport(text: truncate(text), fileName: fileName)
            
        case "xlsx", "xls":
            throw TaskImportError.unsupportedFormat
            
        default:
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                return try await parseTextImport(text: truncate(text), fileName: fileName)
            }
            throw TaskImportError.unsupportedFormat
        }
    }
    
    // MARK: - Private
    
    private func parseTextImport(text: String, fileName: String) async throws -> TaskImportResult {
        let prompt = LookAfterPrompts.taskImportPrompt(fileName: fileName, fileContent: text)
        let response = try await glm.complete(
            prompt: prompt,
            systemPrompt: LookAfterPrompts.structuredOutputSystem,
            tier: .economy
        )
        return try parseResponse(response, fileName: fileName)
    }
    
    private func parseResponse(_ response: String, fileName: String) throws -> TaskImportResult {
        let cleaned = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard
            let data = cleaned.data(using: .utf8),
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let taskArray = json["tasks"] as? [[String: Any]]
        else {
            throw TaskImportError.parseError
        }
        
        let notes = json["importNotes"] as? String ?? "Imported from \(fileName)"
        let drafts = taskArray.compactMap { parseDraft($0) }
        
        guard !drafts.isEmpty else { throw TaskImportError.noTasksFound }
        
        return TaskImportResult(
            tasks: Array(drafts.prefix(50)),
            notes: notes,
            sourceFileName: fileName
        )
    }
    
    private func parseDraft(_ json: [String: Any]) -> ImportedTaskDraft? {
        guard let title = json["title"] as? String,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
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
        
        var deadline: Date?
        if let deadlineStr = json["deadline"] as? String, !deadlineStr.isEmpty, deadlineStr.lowercased() != "null" {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            deadline = formatter.date(from: deadlineStr)
                ?? {
                    let fallback = DateFormatter()
                    fallback.dateFormat = "yyyy-MM-dd"
                    return fallback.date(from: deadlineStr)
                }()
        }
        
        let tags = json["tags"] as? [String] ?? []
        
        return ImportedTaskDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description,
            lifeArea: lifeArea,
            priority: priority,
            difficulty: difficulty,
            estimatedMinutes: TaskDurationPolicy.clamp(estimatedMinutes, allowShortTasks: true),
            deadline: deadline,
            recurrence: recurrence,
            tags: tags
        )
    }
    
    private func truncate(_ text: String) -> String {
        guard text.count > maxTextCharacters else { return text }
        let index = text.index(text.startIndex, offsetBy: maxTextCharacters)
        return String(text[..<index]) + "\n\n[... file truncated for import ...]"
    }
}
