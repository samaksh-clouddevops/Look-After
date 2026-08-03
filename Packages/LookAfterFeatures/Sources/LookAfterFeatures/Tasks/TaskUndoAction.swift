import Foundation
import LookAfterCore

public enum TaskUndoKind: Sendable {
    case completed(
        restoredTask: LifeTask,
        wasInActiveList: Bool,
        activeIndex: Int?,
        spawnedOccurrenceId: String?
    )
    case deleted(
        task: LifeTask,
        wasInActiveList: Bool,
        activeIndex: Int?,
        wasInCompletedList: Bool,
        completedIndex: Int?
    )
}

public struct TaskUndoAction: Identifiable, Sendable {
    public let id: String
    public let message: String
    public let kind: TaskUndoKind

    public init(id: String = UUID().uuidString, message: String, kind: TaskUndoKind) {
        self.id = id
        self.message = message
        self.kind = kind
    }
}
