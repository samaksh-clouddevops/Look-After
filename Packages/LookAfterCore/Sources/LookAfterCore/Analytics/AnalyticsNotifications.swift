import Foundation

public extension Notification.Name {
    /// Posted when task, habit, health, or focus data changes and analytics should refresh.
    static let analyticsDataDidChange = Notification.Name("LifeOSAnalyticsDataDidChange")
    /// Posted when tasks are created, updated, completed, or deleted outside TasksViewModel.
    static let taskListDidChange = Notification.Name("LifeOSTaskListDidChange")
    /// Posted after schedule reconcile completes — consumers should rebuild timeline from reconciled state.
    static let scheduleDidChange = Notification.Name("LifeOSScheduleDidChange")
    /// Posted when medication schedule or adherence changes.
    static let medicationListDidChange = Notification.Name("LifeOSMedicationListDidChange")
    /// Posted when capture is routed to a destination (task, journal, health, inbox review).
    static let captureDidRoute = Notification.Name("LifeOSCaptureDidRoute")
}

public enum CaptureNotificationKey {
    public static let result = "captureRouteResult"
}

public enum AnalyticsDataChangeReason: String, Sendable {
    case taskCompleted
    case habitChanged
    case healthSyncCompleted
    case focusSessionEnded
}
