import Foundation

/// Represents a recurring maintenance task or a shared chore in the Home.
public struct HomeMaintenanceTask: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var intervalDays: Int
    public var lastCompleted: Date?
    public var nextDue: Date
    public var assignedTo: String?
    public var isShared: Bool
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        intervalDays: Int,
        lastCompleted: Date? = nil,
        nextDue: Date,
        assignedTo: String? = nil,
        isShared: Bool = false
    ) {
        self.id = id
        self.title = title
        self.intervalDays = intervalDays
        self.lastCompleted = lastCompleted
        self.nextDue = nextDue
        self.assignedTo = assignedTo
        self.isShared = isShared
    }
    
    /// Returns true if the task is past its due date
    public var isOverdue: Bool {
        return nextDue < Date()
    }
}
