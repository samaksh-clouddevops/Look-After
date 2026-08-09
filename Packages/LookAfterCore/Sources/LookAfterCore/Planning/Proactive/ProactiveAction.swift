import Foundation

/// Unified proactive suggestion — schedule sanity, moments, patterns, and circuit breakers.
public struct ProactiveAction: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case workOnRestDay
        case meetingOutsideOfficeHours
        case duplicateSeries
        case pastDueStillToday
        case fixedTaskMissingTime
        case longEveningGap
        case workAfterWindDown
        case overloadedAfternoon
        case preSleepCrunch
        case highFocusDuringLowEnergy
        case noBreaksInLongBlock
        case tooManyContextSwitches
        case initiationHeavyStack
        case protectedTimeConflict
        case medicationNotScheduled
        case sleepTargetDrift
        case morningPlanReview
        case middayCheckpoint
        case postCompletionMomentum
        case calendarChange
        case waitingMode
        case transitionShield
        case initiationBridge
        case deferralRecovery
        case patternCoach
        case captureResurrection
        case hyperfocusBreak
        case overwhelmCircuitBreaker
        case relationshipDrift
        case lifeAdminBatch
        case badDay
        case emailActionRequired
        case travelDisruption
        case endOfDayClose
        case weekPrimer
        case experimentReminder
        case accountabilityStart
        case bodyDoubleReminder
    }

    public enum Surface: String, Sendable, CaseIterable {
        case banner
        case notification
        case planning
        case autoApplyPreview
    }

    public enum Severity: String, Sendable, CaseIterable {
        case low
        case medium
        case high
    }

    public let id: String
    public let kind: Kind
    public let severity: Severity
    public let message: String
    public let options: [String]
    public let surface: Surface
    public let relatedTaskIDs: [String]
    public let relatedInboxIDs: [String]
    public let expiresAt: Date?
    public let metadata: [String: String]

    public init(
        id: String = UUID().uuidString,
        kind: Kind,
        severity: Severity,
        message: String,
        options: [String],
        surface: Surface = .banner,
        relatedTaskIDs: [String] = [],
        relatedInboxIDs: [String] = [],
        expiresAt: Date? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.message = message
        self.options = options
        self.surface = surface
        self.relatedTaskIDs = relatedTaskIDs
        self.relatedInboxIDs = relatedInboxIDs
        self.expiresAt = expiresAt
        self.metadata = metadata
    }

    public static func from(_ suggestion: ScheduleProactiveSuggestion, surface: Surface = .banner) -> ProactiveAction {
        ProactiveAction(
            id: suggestion.id,
            kind: Kind(rawValue: suggestion.kind.rawValue) ?? .morningPlanReview,
            severity: Severity(rawValue: suggestion.severity.rawValue) ?? .low,
            message: suggestion.message,
            options: suggestion.options,
            surface: surface,
            relatedTaskIDs: suggestion.relatedTaskIDs
        )
    }

    public var asScheduleSuggestion: ScheduleProactiveSuggestion? {
        guard let kind = ScheduleProactiveSuggestion.Kind(rawValue: kind.rawValue) else { return nil }
        return ScheduleProactiveSuggestion(
            id: id,
            kind: kind,
            severity: ScheduleProactiveSuggestion.Severity(rawValue: severity.rawValue) ?? .low,
            message: message,
            options: options,
            relatedTaskIDs: relatedTaskIDs
        )
    }
}
