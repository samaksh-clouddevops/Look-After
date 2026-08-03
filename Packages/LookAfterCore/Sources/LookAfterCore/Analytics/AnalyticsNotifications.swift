import Foundation

public extension Notification.Name {
    /// Posted when task, habit, health, or focus data changes and analytics should refresh.
    static let analyticsDataDidChange = Notification.Name("LifeOSAnalyticsDataDidChange")
    /// Posted when tasks are created, updated, completed, or deleted outside TasksViewModel.
    static let taskListDidChange = Notification.Name("LifeOSTaskListDidChange")
}

public enum AnalyticsDataChangeReason: String, Sendable {
    case taskCompleted
    case habitChanged
    case healthSyncCompleted
    case focusSessionEnded
}
