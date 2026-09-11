import Foundation

// MARK: - Kinds & routing

public enum NotificationKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case morningBriefing
    case brainHero
    case meetingPrep
    case taskDue
    case medication
    case focusBreak
    case transitionShield
    case waitingMode
    case patternInsight
    case initiationBridge
    case wakeRecovery
    case weekPrimer
    case endOfDayClose
    case postCompletionMomentum

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .morningBriefing: return "Morning briefing"
        case .brainHero: return "Brain suggestions"
        case .meetingPrep: return "Meeting prep"
        case .taskDue: return "Task reminders"
        case .medication: return "Medication"
        case .focusBreak: return "Focus breaks"
        case .transitionShield: return "Transition alerts"
        case .waitingMode: return "Waiting-mode tasks"
        case .patternInsight: return "Pattern insights"
        case .initiationBridge: return "Initiation nudges"
        case .wakeRecovery: return "Wake recovery"
        case .weekPrimer: return "Week primer"
        case .endOfDayClose: return "End of day close"
        case .postCompletionMomentum: return "Completion momentum"
        }
    }

    public var priority: Int {
        switch self {
        case .medication: return 1
        case .transitionShield: return 2
        case .meetingPrep: return 3
        case .taskDue: return 4
        case .initiationBridge: return 5
        case .waitingMode: return 6
        case .wakeRecovery: return 6
        case .postCompletionMomentum: return 6
        case .endOfDayClose: return 7
        case .weekPrimer: return 7
        case .morningBriefing: return 8
        case .patternInsight: return 9
        case .brainHero: return 10
        case .focusBreak: return 0
        }
    }

    /// Focus break alerts are session-local and do not count toward the proactive daily cap.
    public var countsTowardDailyCap: Bool {
        self != .focusBreak
    }
}

public enum NotificationRoute: String, Codable, Sendable {
    case briefing
    case brain
    case today
    case task
    case medication
    case focusSession
    case emergency
    case capture
}

// MARK: - Candidate & payload

public struct NotificationCandidate: Identifiable, Sendable, Equatable {
    public let id: String
    public let kind: NotificationKind
    public let title: String
    public let body: String
    public let fireDate: Date
    public let route: NotificationRoute
    public let routePayload: String?
    public let proactiveKind: String?
    public let anchorEventID: String?

    public init(
        id: String,
        kind: NotificationKind,
        title: String,
        body: String,
        fireDate: Date,
        route: NotificationRoute,
        routePayload: String? = nil,
        proactiveKind: String? = nil,
        anchorEventID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.fireDate = fireDate
        self.route = route
        self.routePayload = routePayload
        self.proactiveKind = proactiveKind
        self.anchorEventID = anchorEventID
    }
}

public struct NotificationPayloadKeys {
    public static let kind = "kind"
    public static let route = "route"
    public static let routePayload = "routePayload"
    public static let candidateID = "candidateID"
    public static let proactiveKind = "proactiveKind"
    public static let proactiveActionID = "proactiveActionID"
}

public enum NotificationIdentifier {
    public static let prefix = "lookafter"

    public static func proactive(_ kind: NotificationKind, suffix: String) -> String {
        "\(prefix).proactive.\(kind.rawValue).\(suffix)"
    }

    public static func focusBreak(sessionToken: String) -> String {
        "\(prefix).session.focusBreak.\(sessionToken)"
    }

    public static let proactivePrefix = "\(prefix).proactive."
    public static let focusBreakPrefix = "\(prefix).session.focusBreak."
}

// MARK: - Preferences

public struct NotificationPreferences: Codable, Sendable, Equatable {
    public var globallyEnabled: Bool
    public var categoryEnabled: [String: Bool]

    public init(
        globallyEnabled: Bool = true,
        categoryEnabled: [String: Bool] = [:]
    ) {
        self.globallyEnabled = globallyEnabled
        self.categoryEnabled = categoryEnabled
    }

    public func isEnabled(_ kind: NotificationKind) -> Bool {
        guard globallyEnabled else { return false }
        return categoryEnabled[kind.rawValue, default: true]
    }

    public mutating func setEnabled(_ kind: NotificationKind, _ enabled: Bool) {
        categoryEnabled[kind.rawValue] = enabled
    }

    public static let `default` = NotificationPreferences()
}

// MARK: - Daily budget

public struct ProactiveDailyBudget: Codable, Sendable, Equatable {
    public var dayKey: String
    public var deliveredCount: Int
    public var dismissedCandidateIDs: [String]
    public var snoozedCandidateIDs: [String: Date]

    public init(
        dayKey: String,
        deliveredCount: Int = 0,
        dismissedCandidateIDs: [String] = [],
        snoozedCandidateIDs: [String: Date] = [:]
    ) {
        self.dayKey = dayKey
        self.deliveredCount = deliveredCount
        self.dismissedCandidateIDs = dismissedCandidateIDs
        self.snoozedCandidateIDs = snoozedCandidateIDs
    }

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

public enum NotificationPolicy {
    public static let maxProactivePerDay = 2
    public static let snoozeMinutes = 15
    public static let meetingPrepLeadMinutes = 20
    public static let meetingPrepWindowMin = 15
    public static let meetingPrepWindowMax = 45
}

// MARK: - Refresh input

public struct NotificationRefreshInput: Sendable {
    public var now: Date
    public var medications: [Medication]
    public var tasks: [LifeTask]
    public var nextCalendarEvent: CalendarEventReference?
    public var postWake: PostWakeDetector.Result
    public var heroTaskTitle: String?
    public var heroTaskId: String?
    public var focusSessionActive: Bool
    public var focusBreakFireDate: Date?
    public var focusSessionToken: String?
    public var userDisplayName: String
    public var proactiveActions: [ProactiveAction]
    /// One lean supervisor line (fault or pull) — replaces generic morning body when set.
    public var dayAuditLeanBody: String?

    public init(
        now: Date = Date(),
        medications: [Medication] = [],
        tasks: [LifeTask] = [],
        nextCalendarEvent: CalendarEventReference? = nil,
        postWake: PostWakeDetector.Result = .inactive,
        heroTaskTitle: String? = nil,
        heroTaskId: String? = nil,
        focusSessionActive: Bool = false,
        focusBreakFireDate: Date? = nil,
        focusSessionToken: String? = nil,
        userDisplayName: String = "",
        proactiveActions: [ProactiveAction] = [],
        dayAuditLeanBody: String? = nil
    ) {
        self.now = now
        self.medications = medications
        self.tasks = tasks
        self.nextCalendarEvent = nextCalendarEvent
        self.postWake = postWake
        self.heroTaskTitle = heroTaskTitle
        self.heroTaskId = heroTaskId
        self.focusSessionActive = focusSessionActive
        self.focusBreakFireDate = focusBreakFireDate
        self.focusSessionToken = focusSessionToken
        self.userDisplayName = userDisplayName
        self.proactiveActions = proactiveActions
        self.dayAuditLeanBody = dayAuditLeanBody
    }
}
