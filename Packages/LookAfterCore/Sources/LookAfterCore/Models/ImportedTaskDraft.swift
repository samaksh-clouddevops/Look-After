import Foundation
import LookAfterCore

/// A task parsed from an imported file, before conversion to LifeTask.
public struct ImportedTaskDraft: Identifiable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var description: String
    public var lifeArea: LifeArea
    public var priority: Priority
    public var difficulty: TaskDifficulty
    public var estimatedMinutes: Int
    public var deadline: Date?
    public var recurrence: TaskRecurrence
    public var tags: [String]
    public var selected: Bool
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        description: String = "",
        lifeArea: LifeArea = .personal,
        priority: Priority = .medium,
        difficulty: TaskDifficulty = .medium,
        estimatedMinutes: Int = 30,
        deadline: Date? = nil,
        recurrence: TaskRecurrence = .none,
        tags: [String] = [],
        selected: Bool = true
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.lifeArea = lifeArea
        self.priority = priority
        self.difficulty = difficulty
        self.estimatedMinutes = estimatedMinutes
        self.deadline = deadline
        self.recurrence = recurrence
        self.tags = tags
        self.selected = selected
    }
    
    public func toLifeTask(userId: String) -> LifeTask {
        LifeTask(
            title: title,
            description: description,
            lifeArea: lifeArea,
            priority: priority,
            difficulty: difficulty,
            estimatedMinutes: estimatedMinutes,
            requiredEnergy: difficulty.minimumEnergy,
            deadline: deadline,
            tags: tags,
            recurrence: recurrence,
            userId: userId
        )
    }
}

public struct TaskImportResult: Sendable {
    public var tasks: [ImportedTaskDraft]
    public var notes: String
    public var sourceFileName: String
    
    public init(tasks: [ImportedTaskDraft], notes: String, sourceFileName: String) {
        self.tasks = tasks
        self.notes = notes
        self.sourceFileName = sourceFileName
    }
}

public enum TaskImportError: Error, LocalizedError {
    case emptyFile
    case unsupportedFormat
    case parseError
    case noTasksFound
    case apiKeyMissing
    
    public var errorDescription: String? {
        switch self {
        case .emptyFile: return "The file appears to be empty."
        case .unsupportedFormat: return "This file type is not supported. Use .txt, .csv, or .xlsx."
        case .parseError: return "The AI could not parse the file. Check the format and try again."
        case .noTasksFound: return "No tasks were found in this file."
        case .apiKeyMissing: return "Add your GLM API key in Settings first."
        }
    }
}
