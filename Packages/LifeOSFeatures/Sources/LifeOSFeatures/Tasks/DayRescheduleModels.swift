import Foundation
import LifeOSCore

/// A single proposed time change for one task.
public struct DayScheduleChange: Identifiable, Sendable, Equatable {
    public let id: String
    public let taskTitle: String
    public let previousTime: Date?
    public let proposedTime: Date
    public let reason: String
    public let isFixed: Bool
    public let wasMoved: Bool

    public init(
        id: String,
        taskTitle: String,
        previousTime: Date?,
        proposedTime: Date,
        reason: String,
        isFixed: Bool,
        wasMoved: Bool
    ) {
        self.id = id
        self.taskTitle = taskTitle
        self.previousTime = previousTime
        self.proposedTime = proposedTime
        self.reason = reason
        self.isFixed = isFixed
        self.wasMoved = wasMoved
    }
}

/// Preview payload returned before applying an AI-generated day plan.
public struct DayRescheduleProposal: Identifiable, Sendable, Equatable {
    public let id: String
    public let summary: String
    public let changes: [DayScheduleChange]
    public let suggestions: [DayScheduleSuggestion]

    public init(
        id: String = UUID().uuidString,
        summary: String,
        changes: [DayScheduleChange],
        suggestions: [DayScheduleSuggestion]
    ) {
        self.id = id
        self.summary = summary
        self.changes = changes
        self.suggestions = suggestions
    }

    public var movedCount: Int {
        changes.filter(\.wasMoved).count
    }
}

/// Internal suggestion payload used to apply schedule updates.
public struct DayScheduleSuggestion: Sendable, Equatable {
    public let id: String
    public let startHour: Int
    public let startMinute: Int
    public let reason: String

    public init(id: String, startHour: Int, startMinute: Int, reason: String = "") {
        self.id = id
        self.startHour = startHour
        self.startMinute = startMinute
        self.reason = reason
    }
}
