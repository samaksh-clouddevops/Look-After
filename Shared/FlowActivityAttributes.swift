import Foundation
import ActivityKit

/// Live Activity shown during a focus / pomodoro session.
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var taskTitle: String
        var sessionEndDate: Date
        var isPaused: Bool
        var isOnBreak: Bool
        var sessionLabel: String
        var remainingLabel: String
    }
    
    var taskTitle: String
    var sessionNumber: Int
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
