import Foundation

/// Typed schedule semantics for timeline events — replaces subtitle string matching.
public enum TimelineScheduleKind: String, Codable, Sendable, Equatable, Hashable {
    case fixedWindow
    case flexibleDay
    case floating
    case completed
    case grouped
}

public extension TimelineScheduleKind {
    var isFlexibleToday: Bool {
        self == .flexibleDay || self == .floating
    }
}
