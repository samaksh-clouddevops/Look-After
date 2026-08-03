import Foundation
import LookAfterCore

/// UI-ready Brain tab state — built from orchestrator + task data.
public struct BrainPresentation: Sendable, Equatable {
    public var greeting: String
    public var readinessLabel: String
    public var hero: BrainHeroPresentation?
    public var backupTasks: [LifeTask]
    public var resume: BrainResumePresentation?
    public var capacity: BrainCapacityPresentation
    public var headsUp: [BrainHeadsUpItem]
    public var flowWindowLabel: String?
    public var coachMoment: String?
    public var confidenceLabel: String?

    public static let empty = BrainPresentation(
        greeting: "Hello",
        readinessLabel: "Ready",
        hero: nil,
        backupTasks: [],
        resume: nil,
        capacity: .empty,
        headsUp: [],
        flowWindowLabel: nil,
        coachMoment: nil,
        confidenceLabel: nil
    )
}

public struct BrainHeroPresentation: Sendable, Equatable {
    public var task: LifeTask?
    public var title: String
    public var supportingLine: String
    public var scheduledLabel: String?
    public var durationMinutes: Int?
    public var whyReasons: [String]
    public var buttonLabel: String
    public var isPastDue: Bool
    public var kind: LifeTimelineEventKind

    public var hasTask: Bool { task != nil }
}

public struct BrainResumePresentation: Sendable, Equatable {
    public var title: String
    public var detail: String
    public var elapsedLabel: String?
    public var pausedAgoLabel: String?
    public var taskID: String?
}

public struct BrainCapacityPresentation: Sendable, Equatable {
    public var bandLabel: String
    public var tagline: String
    public var freeMinutesLabel: String?
    public var sleepLabel: String?

    public static let empty = BrainCapacityPresentation(
        bandLabel: "Moderate Capacity",
        tagline: "Good for planning and admin.",
        freeMinutesLabel: nil,
        sleepLabel: nil
    )
}

public struct BrainHeadsUpItem: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable {
        case medication
        case bill
        case calendar
    }

    public let id: String
    public var kind: Kind
    public var title: String
    public var subtitle: String
    public var actionLabel: String?
    public var medicationID: String?
    public var taskID: String?

    public init(
        id: String = UUID().uuidString,
        kind: Kind,
        title: String,
        subtitle: String,
        actionLabel: String? = nil,
        medicationID: String? = nil,
        taskID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.actionLabel = actionLabel
        self.medicationID = medicationID
        self.taskID = taskID
    }
}
