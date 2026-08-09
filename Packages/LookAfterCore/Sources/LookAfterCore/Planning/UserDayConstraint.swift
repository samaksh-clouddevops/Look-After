import Foundation

/// User-declared day context that affects scheduling (post-wake, going out, etc.).
public enum UserDayConstraintKind: String, Codable, Sendable, Equatable {
    case postWake
    case goingOut
}

public struct UserDayConstraint: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: UserDayConstraintKind
    public var day: Date
    public var wakeTime: Date?
    public var departureTime: Date?
    public var durationMinutes: Int?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        kind: UserDayConstraintKind,
        day: Date,
        wakeTime: Date? = nil,
        departureTime: Date? = nil,
        durationMinutes: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.day = day
        self.wakeTime = wakeTime
        self.departureTime = departureTime
        self.durationMinutes = durationMinutes
        self.createdAt = createdAt
    }

    public var awayWindowEnd: Date? {
        guard kind == .goingOut,
              let departure = departureTime,
              let minutes = durationMinutes else { return nil }
        return departure.addingTimeInterval(TimeInterval(minutes * 60))
    }

    public static func postWake(wakeTime: Date, calendar: Calendar = .current) -> UserDayConstraint {
        UserDayConstraint(
            kind: .postWake,
            day: calendar.startOfDay(for: wakeTime),
            wakeTime: wakeTime
        )
    }

    public static func goingOut(
        departure: Date,
        durationMinutes: Int,
        calendar: Calendar = .current
    ) -> UserDayConstraint {
        UserDayConstraint(
            kind: .goingOut,
            day: calendar.startOfDay(for: departure),
            departureTime: departure,
            durationMinutes: max(durationMinutes, 15)
        )
    }
}
