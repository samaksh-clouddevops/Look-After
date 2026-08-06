import Foundation

// MARK: - Expiration

/// When an incomplete task dies instead of parking / rolling forever.
public enum TaskExpirationPolicy: Sendable, Equatable, Hashable {
    /// Survives for multi-day rollover (subject to collision + horizon).
    case infinite
    /// Dies at local midnight if not completed — never rolls.
    case endOfDay
    /// Dies if not started within `minutes` of `scheduledTime`.
    case strictWindow(minutes: Int)

    public static let `default`: TaskExpirationPolicy = .infinite
}

extension TaskExpirationPolicy: Codable {
    private enum CodingKeys: String, CodingKey { case type, minutes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "endOfDay": self = .endOfDay
        case "strictWindow":
            self = .strictWindow(minutes: try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 90)
        default: self = .infinite
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .infinite:
            try c.encode("infinite", forKey: .type)
        case .endOfDay:
            try c.encode("endOfDay", forKey: .type)
        case .strictWindow(let minutes):
            try c.encode("strictWindow", forKey: .type)
            try c.encode(minutes, forKey: .minutes)
        }
    }
}

// MARK: - Bounding box

/// Same-day fence so Lunch cannot slide into Dinner.
public struct TemporalBoundingBox: Codable, Sendable, Equatable, Hashable {
    public var earliestStartHour: Int
    public var latestStartHour: Int

    public init(earliestStartHour: Int, latestStartHour: Int) {
        self.earliestStartHour = min(23, max(0, earliestStartHour))
        self.latestStartHour = min(23, max(self.earliestStartHour, latestStartHour))
    }

    public func contains(start: Date, calendar: Calendar = .current) -> Bool {
        let h = calendar.component(.hour, from: start)
        let m = calendar.component(.minute, from: start)
        let fractional = Double(h) + Double(m) / 60.0
        return fractional >= Double(earliestStartHour) && fractional <= Double(latestStartHour) + 0.99
    }

    public func clampStart(_ start: Date, on day: Date, calendar: Calendar = .current) -> Date? {
        let dayStart = calendar.startOfDay(for: day)
        guard let earliest = calendar.date(bySettingHour: earliestStartHour, minute: 0, second: 0, of: dayStart),
              let latest = calendar.date(bySettingHour: latestStartHour, minute: 59, second: 0, of: dayStart) else {
            return nil
        }
        if start < earliest { return earliest }
        if start > latest { return nil } // cannot place after fence
        return start
    }
}

// MARK: - Semantic collision

/// How rollovers interact with an existing same-hash instance on the destination day.
public enum SemanticCollisionStrategy: String, Codable, Sendable, Equatable {
    /// Allow multiple (e.g. "Read 10 pages").
    case allowMultiple
    /// Drop the older incomplete if today already has this activity (workout, meds).
    case dropOldest
    /// Prefer the old incomplete; block the newer scheduled instance (rare).
    case blockNewest
}

// MARK: - Defaults from semantics

public enum TaskEphemeralityDefaults {
    public static func expiration(for task: LifeTask) -> TaskExpirationPolicy {
        if let explicit = task.expirationPolicy { return explicit }
        switch task.semanticProfile?.semanticType {
        case .medication:
            return .strictWindow(minutes: 90)
        case .selfCare, .physicalActivity:
            return .endOfDay
        case .errand:
            return task.estimatedMinutes <= 45 ? .endOfDay : .infinite
        default:
            return .infinite
        }
    }

    /// Applies semantic-derived scheduling policy to a task record (templates + occurrences).
    public static func enrich(_ task: LifeTask) -> LifeTask {
        var enriched = task
        enriched.semanticProfile = TaskSemanticProfileBuilder.classificationProfile(for: enriched)
        if enriched.expirationPolicy == nil {
            enriched.expirationPolicy = expiration(for: enriched)
        }
        if enriched.collisionStrategy == nil {
            enriched.collisionStrategy = collisionStrategy(for: enriched)
        }
        if enriched.temporalBoundingBox == nil {
            enriched.temporalBoundingBox = boundingBox(for: enriched)
        }
        return enriched
    }

    /// Copies template scheduling policy onto a materialized occurrence.
    public static func applyTemplatePolicy(_ occurrence: LifeTask, from template: LifeTask) -> LifeTask {
        let enrichedTemplate = enrich(template)
        var enrichedOccurrence = occurrence
        enrichedOccurrence.semanticProfile = enrichedTemplate.semanticProfile
        enrichedOccurrence.expirationPolicy = enrichedTemplate.expirationPolicy
        enrichedOccurrence.collisionStrategy = enrichedTemplate.collisionStrategy
        enrichedOccurrence.temporalBoundingBox = enrichedTemplate.temporalBoundingBox
        return enrichedOccurrence
    }

    public static func boundingBox(for task: LifeTask) -> TemporalBoundingBox? {
        if let box = task.temporalBoundingBox { return box }
        switch task.semanticProfile?.semanticType {
        case .selfCare:
            let title = task.title.lowercased()
            if title.contains("evening") || title.contains("night") {
                return TemporalBoundingBox(earliestStartHour: 17, latestStartHour: 23)
            }
            if title.contains("morning") {
                return TemporalBoundingBox(earliestStartHour: 5, latestStartHour: 12)
            }
            return TemporalBoundingBox(earliestStartHour: 6, latestStartHour: 23)
        case .errand where task.semanticProfile?.subtype == "meal":
            return mealBoundingBox(title: task.title.lowercased())
        default:
            break
        }
        let title = task.title.lowercased()
        if title.contains("lunch") || title.contains("brunch") {
            return TemporalBoundingBox(earliestStartHour: 11, latestStartHour: 15)
        }
        if title.contains("breakfast") || title.contains("coffee") {
            return TemporalBoundingBox(earliestStartHour: 5, latestStartHour: 11)
        }
        if title.contains("snack") {
            return TemporalBoundingBox(earliestStartHour: 14, latestStartHour: 18)
        }
        if title.contains("dinner") || title.contains("supper") {
            return TemporalBoundingBox(earliestStartHour: 17, latestStartHour: 21)
        }
        if task.semanticProfile?.semanticType == .medication {
            return TemporalBoundingBox(earliestStartHour: 6, latestStartHour: 22)
        }
        return nil
    }

    private static func mealBoundingBox(title: String) -> TemporalBoundingBox {
        if title.contains("lunch") || title.contains("brunch") {
            return TemporalBoundingBox(earliestStartHour: 11, latestStartHour: 15)
        }
        if title.contains("breakfast") || title.contains("coffee") {
            return TemporalBoundingBox(earliestStartHour: 5, latestStartHour: 11)
        }
        if title.contains("snack") {
            return TemporalBoundingBox(earliestStartHour: 14, latestStartHour: 18)
        }
        if title.contains("dinner") || title.contains("supper") {
            return TemporalBoundingBox(earliestStartHour: 17, latestStartHour: 21)
        }
        return TemporalBoundingBox(earliestStartHour: 7, latestStartHour: 21)
    }

    public static func collisionStrategy(for task: LifeTask) -> SemanticCollisionStrategy {
        if let explicit = task.collisionStrategy { return explicit }
        switch task.semanticProfile?.semanticType {
        case .physicalActivity, .medication, .selfCare:
            return .dropOldest
        case .deepWork, .learning, .creative, .administrative, .communication, .errand, .generic, .none:
            return .allowMultiple
        }
    }
}

// MARK: - Reaper evaluation

public enum TaskReaper {
    public enum Verdict: Sendable, Equatable {
        case alive
        case expire
        case supersede
    }

    /// Stage 0: should this task still compete for time?
    public static func verdict(
        for task: LifeTask,
        now: Date = Date(),
        destinationDayTasks: [LifeTask] = [],
        calendar: Calendar = .current
    ) -> Verdict {
        let policy = TaskEphemeralityDefaults.expiration(for: task)

        switch policy {
        case .infinite:
            break
        case .endOfDay:
            if let scheduledDate = task.scheduledDate {
                let day = calendar.startOfDay(for: scheduledDate)
                let today = calendar.startOfDay(for: now)
                if day < today { return .expire }
            }
        case .strictWindow(let minutes):
            if let start = task.scheduledTime {
                let deadline = start.addingTimeInterval(TimeInterval(minutes * 60))
                if now > deadline { return .expire }
            }
        }

        // Semantic collision against destination day (rollover target).
        let strategy = TaskEphemeralityDefaults.collisionStrategy(for: task)
        if strategy == .dropOldest {
            let key = collisionKey(for: task)
            let hasDup = destinationDayTasks.contains {
                $0.id != task.id
                    && $0.status.isActive
                    && collisionKey(for: $0) == key
            }
            if hasDup { return .supersede }
        }

        return .alive
    }

    /// Type-level key for wellness/meds so "Push" vs "Pull" still collide as one gym session.
    public static func collisionKey(for task: LifeTask) -> String {
        let type = task.semanticProfile?.semanticType
            ?? TaskSemanticProfileBuilder.build(from: task).semanticType
        switch type {
        case .physicalActivity:
            return "physicalActivity|session"
        case .medication:
            return "medication|\(BehavioralSemanticHash.make(for: task))"
        case .selfCare:
            return "selfCare|\(BehavioralSemanticHash.make(for: task))"
        default:
            return BehavioralSemanticHash.make(for: task)
        }
    }

    /// Whether a proposed same-day start respects the bounding box.
    public static func allowsStart(
        _ start: Date,
        for task: LifeTask,
        calendar: Calendar = .current
    ) -> Bool {
        guard let box = TaskEphemeralityDefaults.boundingBox(for: task) else { return true }
        return box.contains(start: start, calendar: calendar)
    }
}
