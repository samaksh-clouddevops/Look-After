import Foundation
import ActivityKit

/// Live Activity for focus sessions and schedule-driven execution blocks.
/// Supports manual ADHD pomodoro (legacy fields) and Execution Layer surfaces.
struct FocusActivityAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        var taskTitle: String
        var sessionEndDate: Date
        var isPaused: Bool
        var isOnBreak: Bool
        var sessionLabel: String
        var remainingLabel: String

        // Execution Layer projections (defaults keep pomodoro callers compiling).
        var constraintType: String
        var progressFraction: Double
        var nextUpSummary: String
        var categoryRaw: String
        var surfaceModeRaw: String
        var showsStrictCountdown: Bool

        init(
            taskTitle: String,
            sessionEndDate: Date,
            isPaused: Bool = false,
            isOnBreak: Bool = false,
            sessionLabel: String = "Deep Focus",
            remainingLabel: String = "",
            constraintType: String = "Flexible",
            progressFraction: Double = 0,
            nextUpSummary: String = "",
            categoryRaw: String = "deepWork",
            surfaceModeRaw: String = "flexible",
            showsStrictCountdown: Bool = true
        ) {
            self.taskTitle = taskTitle
            self.sessionEndDate = sessionEndDate
            self.isPaused = isPaused
            self.isOnBreak = isOnBreak
            self.sessionLabel = sessionLabel
            self.remainingLabel = remainingLabel
            self.constraintType = constraintType
            self.progressFraction = min(1, max(0, progressFraction))
            self.nextUpSummary = nextUpSummary
            self.categoryRaw = categoryRaw
            self.surfaceModeRaw = surfaceModeRaw
            self.showsStrictCountdown = showsStrictCountdown
        }
    }

    /// Static attributes fixed for the life of one Activity instance.
    var taskTitle: String
    var sessionNumber: Int
    /// SF Symbol for Dynamic Island leading compact.
    var categoryIcon: String

    init(taskTitle: String, sessionNumber: Int = 1, categoryIcon: String = "brain.head.profile") {
        self.taskTitle = taskTitle
        self.sessionNumber = sessionNumber
        self.categoryIcon = categoryIcon
    }
}

/// Pinned "Optimal Next Step" on Lock Screen / Dynamic Island.
struct NowPinActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var topTaskTitle: String
        var energyScore: Int
        var energyLevel: String
        var recommendation: String
        var estimatedMinutes: Int
    }

    var pinnedAt: Date
}
