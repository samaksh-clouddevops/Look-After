import Foundation
import LifeOSCore

/// Creates a LifeTask from AI-processed inbox output.
public struct InboxTaskDraft: Sendable {
    public var title: String
    public var lifeArea: LifeArea?
    public var priority: Priority?
    public var difficulty: TaskDifficulty?
    public var estimatedMinutes: Int

    public init(
        title: String,
        lifeArea: LifeArea? = nil,
        priority: Priority? = nil,
        difficulty: TaskDifficulty? = nil,
        estimatedMinutes: Int = 15
    ) {
        self.title = title
        self.lifeArea = lifeArea
        self.priority = priority
        self.difficulty = difficulty
        self.estimatedMinutes = estimatedMinutes
    }
}
