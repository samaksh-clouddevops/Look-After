import Foundation

// MARK: - Life Model

/// Compiled representation of the user's life — identity, blocks, and commitments.
public struct LifeModel: Codable, Sendable, Equatable {
    public var rawMarkdown: String
    public var compiledAt: Date
    public var identity: LifeIdentity
    public var priorities: [String]
    public var timeBlocks: [ProtectedTimeBlock]
    public var commitments: [LifeCommitment]
    public var adhdRules: String
    public var decisionFramework: [String]
    public var coachingRules: String

    public init(
        rawMarkdown: String = "",
        compiledAt: Date = Date(),
        identity: LifeIdentity = LifeIdentity(),
        priorities: [String] = [],
        timeBlocks: [ProtectedTimeBlock] = [],
        commitments: [LifeCommitment] = [],
        adhdRules: String = "",
        decisionFramework: [String] = [],
        coachingRules: String = ""
    ) {
        self.rawMarkdown = rawMarkdown
        self.compiledAt = compiledAt
        self.identity = identity
        self.priorities = priorities
        self.timeBlocks = timeBlocks
        self.commitments = commitments
        self.adhdRules = adhdRules
        self.decisionFramework = decisionFramework
        self.coachingRules = coachingRules
    }

    public var isEmpty: Bool {
        rawMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && timeBlocks.isEmpty
            && commitments.isEmpty
    }

    public var hasContent: Bool { !isEmpty }

    /// Stable tag for tasks materialized from this model.
    public static let commitmentTaskTag = "life-commitment"
    public static let commitmentIDPrefix = "life-commitment:"

    public func commitmentID(for title: String) -> String {
        Self.commitmentIDPrefix + title.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
    }

    public func block(matching label: String) -> ProtectedTimeBlock? {
        let normalized = label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return timeBlocks.first {
            $0.label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalized
        }
    }

    public func creativeBlocks() -> [ProtectedTimeBlock] {
        timeBlocks.filter { $0.isCreativeWindow }
    }

    public func nonNegotiableBlocks() -> [ProtectedTimeBlock] {
        timeBlocks.filter { $0.protection == .neverSchedule }
    }
}

// MARK: - Identity

public struct LifeIdentity: Codable, Sendable, Equatable {
    public var name: String
    public var roleFraming: String
    public var mission: String
    public var longTermVision: String

    public init(
        name: String = "",
        roleFraming: String = "",
        mission: String = "",
        longTermVision: String = ""
    ) {
        self.name = name
        self.roleFraming = roleFraming
        self.mission = mission
        self.longTermVision = longTermVision
    }
}

// MARK: - Time blocks

public enum BlockProtection: String, Codable, Sendable, CaseIterable {
    case neverSchedule = "never_schedule"
    case priorityOnly = "priority_only"
    case flexible = "flexible"
    case contextOnly = "context_only"
}

public struct WeekdaySet: Codable, Sendable, Equatable {
    public var monday: Bool
    public var tuesday: Bool
    public var wednesday: Bool
    public var thursday: Bool
    public var friday: Bool
    public var saturday: Bool
    public var sunday: Bool

    public init(
        monday: Bool = true,
        tuesday: Bool = true,
        wednesday: Bool = true,
        thursday: Bool = true,
        friday: Bool = true,
        saturday: Bool = false,
        sunday: Bool = false
    ) {
        self.monday = monday
        self.tuesday = tuesday
        self.wednesday = wednesday
        self.thursday = thursday
        self.friday = friday
        self.saturday = saturday
        self.sunday = sunday
    }

    public static var weekdays: WeekdaySet {
        WeekdaySet(saturday: false, sunday: false)
    }

    public static var weekends: WeekdaySet {
        WeekdaySet(monday: false, tuesday: false, wednesday: false, thursday: false, friday: false, saturday: true, sunday: true)
    }

    public static var everyDay: WeekdaySet {
        WeekdaySet(saturday: true, sunday: true)
    }

    public func includes(_ date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        switch weekday {
        case 1: return sunday
        case 2: return monday
        case 3: return tuesday
        case 4: return wednesday
        case 5: return thursday
        case 6: return friday
        case 7: return saturday
        default: return false
        }
    }
}

public struct ProtectedTimeBlock: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var days: WeekdaySet
    public var startHour: Int
    public var startMinute: Int
    public var endHour: Int
    public var endMinute: Int
    public var protection: BlockProtection
    public var priorityOrder: [String]?

    public init(
        id: String? = nil,
        label: String,
        days: WeekdaySet = .weekdays,
        startHour: Int,
        startMinute: Int = 0,
        endHour: Int,
        endMinute: Int = 0,
        protection: BlockProtection = .flexible,
        priorityOrder: [String]? = nil
    ) {
        self.id = id ?? label.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
        self.label = label
        self.days = days
        self.startHour = min(max(startHour, 0), 23)
        self.startMinute = min(max(startMinute, 0), 59)
        self.endHour = min(max(endHour, 0), 23)
        self.endMinute = min(max(endMinute, 0), 59)
        self.protection = protection
        self.priorityOrder = priorityOrder
    }

    public var isCreativeWindow: Bool {
        let lower = label.lowercased()
        return lower.contains("creative") || lower.contains("deep work") || !(priorityOrder ?? []).isEmpty
    }

    public var startMinutesFromMidnight: Int { startHour * 60 + startMinute }
    public var endMinutesFromMidnight: Int { endHour * 60 + endMinute }

    public func asWorkHours() -> PlanningSchedulePolicy.WorkHours {
        PlanningSchedulePolicy.WorkHours(
            startHour: startHour,
            startMinute: startMinute,
            endHour: endHour,
            endMinute: endMinute
        )
    }

    public func timeRangeLabel() -> String {
        "\(UserLifeProfile.formatTime(hour: startHour, minute: startMinute)) – \(UserLifeProfile.formatTime(hour: endHour, minute: endMinute))"
    }
}

// MARK: - Commitments

public enum CommitmentFrequency: Codable, Sendable, Equatable {
    case daily
    case weekdays
    case weekends
    case weekly(count: Int)
    case customDays(perWeek: Int)

    private enum CodingKeys: String, CodingKey {
        case kind, count
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "daily": self = .daily
        case "weekdays": self = .weekdays
        case "weekends": self = .weekends
        case "weekly":
            self = .weekly(count: try container.decodeIfPresent(Int.self, forKey: .count) ?? 1)
        case "customDays":
            self = .customDays(perWeek: try container.decodeIfPresent(Int.self, forKey: .count) ?? 3)
        default: self = .weekdays
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .daily:
            try container.encode("daily", forKey: .kind)
        case .weekdays:
            try container.encode("weekdays", forKey: .kind)
        case .weekends:
            try container.encode("weekends", forKey: .kind)
        case .weekly(let count):
            try container.encode("weekly", forKey: .kind)
            try container.encode(count, forKey: .count)
        case .customDays(let perWeek):
            try container.encode("customDays", forKey: .kind)
            try container.encode(perWeek, forKey: .count)
        }
    }

    public func applies(on date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .daily: return true
        case .weekdays: return !calendar.isDateInWeekend(date)
        case .weekends: return calendar.isDateInWeekend(date)
        case .weekly, .customDays: return true
        }
    }

    public var recurrence: TaskRecurrence {
        switch self {
        case .daily: return .daily
        case .weekdays: return .weekdays
        case .weekends: return .weekends
        case .weekly, .customDays: return .weekly
        }
    }
}

public struct LifeCommitment: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var lifeArea: LifeArea
    public var frequency: CommitmentFrequency
    public var preferredBlockLabel: String?
    public var defaultMinutes: Int
    public var priority: Int
    public var isNonNegotiable: Bool

    public init(
        id: String? = nil,
        title: String,
        lifeArea: LifeArea = .creativity,
        frequency: CommitmentFrequency = .weekdays,
        preferredBlockLabel: String? = nil,
        defaultMinutes: Int = 30,
        priority: Int = 1,
        isNonNegotiable: Bool = false
    ) {
        self.id = id ?? title.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
        self.title = title
        self.lifeArea = lifeArea
        self.frequency = frequency
        self.preferredBlockLabel = preferredBlockLabel
        self.defaultMinutes = max(defaultMinutes, 5)
        self.priority = priority
        self.isNonNegotiable = isNonNegotiable
    }
}
