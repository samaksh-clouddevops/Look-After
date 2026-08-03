import Foundation
import LifeOSCore

public struct MorningDayBriefing: Sendable, Equatable {
    public var headline: String
    public var introLine: String
    public var sleepLine: String?
    public var idealSleepLine: String?
    public var idealBedtime: Date?
    public var capacityLabel: String
    public var capacityTagline: String
    public var freeTimeLabel: String?
    public var nextEventLabel: String?
    public var focusWindowLabel: String?
    public var workEndLabel: String?
    public var completedCount: Int
    public var remainingCount: Int
    public var overdueCount: Int
    public var plannedMinutesRemaining: Int
    public var planItems: [MorningPlanItem]
    public var pendingHighlights: [String]

    public static let empty = MorningDayBriefing(
        headline: "Your day",
        introLine: "Here is what today looks like.",
        sleepLine: nil,
        idealSleepLine: nil,
        idealBedtime: nil,
        capacityLabel: ExecutiveCapacityBand.moderateCapacity.displayLabel,
        capacityTagline: ExecutiveCapacityBand.moderateCapacity.tagline,
        freeTimeLabel: nil,
        nextEventLabel: nil,
        focusWindowLabel: nil,
        workEndLabel: nil,
        completedCount: 0,
        remainingCount: 0,
        overdueCount: 0,
        plannedMinutesRemaining: 0,
        planItems: [],
        pendingHighlights: []
    )
}

public struct MorningPlanItem: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable {
        case task
        case calendar
        case medication
        case routine
        case bill
    }

    public let id: String
    public var timeLabel: String?
    public var title: String
    public var subtitle: String?
    public var isCompleted: Bool
    public var kind: Kind

    public init(
        id: String,
        timeLabel: String? = nil,
        title: String,
        subtitle: String? = nil,
        isCompleted: Bool = false,
        kind: Kind = .task
    ) {
        self.id = id
        self.timeLabel = timeLabel
        self.title = title
        self.subtitle = subtitle
        self.isCompleted = isCompleted
        self.kind = kind
    }
}
