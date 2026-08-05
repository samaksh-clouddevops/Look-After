import Foundation

/// How tightly a timeline block is locked to its scheduled slot.
///
/// - `anchored`: Immovable — meetings, fixed commitments. Vertical drag rubber-bands only.
/// - `flexible`: Preferred slot — AI may reorder; user drag tracks 1:1.
/// - `fluid`: Soft intent — freely movable; visual lightness while dragging.
public enum TimeConstraint: String, Equatable, Codable, CaseIterable, Sendable, Identifiable {
    case anchored
    case flexible
    case fluid

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .anchored: return "Anchored"
        case .flexible: return "Flexible"
        case .fluid: return "Fluid"
        }
    }

    public var accessibilityDescription: String {
        switch self {
        case .anchored:
            return "Anchored to this time. Locked start."
        case .flexible:
            return "Flexible. Preferred time but can move."
        case .fluid:
            return "Fluid. Soft time intent."
        }
    }

    /// Steps toward a firmer lock (fluid → flexible → anchored).
    public func hardened() -> TimeConstraint {
        switch self {
        case .fluid: return .flexible
        case .flexible: return .anchored
        case .anchored: return .anchored
        }
    }

    /// Steps toward a looser lock (anchored → flexible → fluid).
    public func softened() -> TimeConstraint {
        switch self {
        case .anchored: return .flexible
        case .flexible: return .fluid
        case .fluid: return .fluid
        }
    }

    public var canHarden: Bool { self != .anchored }
    public var canSoften: Bool { self != .fluid }

    /// Maps legacy scheduling modes onto the semantic constraint ladder.
    public static func from(schedulingMode: TaskSchedulingMode?) -> TimeConstraint {
        switch schedulingMode {
        case .fixedTime: return .anchored
        case .flexible, .none: return .flexible
        }
    }

    /// Keeps TaskSchedulingMode in sync for existing scheduler paths.
    public var asSchedulingMode: TaskSchedulingMode {
        switch self {
        case .anchored: return .fixedTime
        case .flexible, .fluid: return .flexible
        }
    }

    /// Whether the day scheduler may auto-move this block.
    public var isSchedulerMovable: Bool {
        switch self {
        case .anchored: return false
        case .flexible, .fluid: return true
        }
    }
}

// MARK: - Physics constants (pure domain — used by UI InteractionEngine)

public enum TimeConstraintPhysics: Sendable {
    /// Max visual offset (pt) when dragging an anchored block.
    public static let anchoredMaxTranslation: Double = 15
    /// Horizontal swipe distance (pt) to mutate constraint.
    public static let swipeThreshold: Double = 56
    /// Fluid drag visual dimming.
    public static let fluidDragOpacity: Double = 0.6
    /// Fluid drag visual scale.
    public static let fluidDragScale: Double = 0.98

    /// Logarithmic rubber-band: large finger travel → at most `max` points of motion.
    public static func anchoredTranslation(rawDelta: Double, max: Double = anchoredMaxTranslation) -> Double {
        guard rawDelta != 0 else { return 0 }
        let sign: Double = rawDelta < 0 ? -1 : 1
        let magnitude = abs(rawDelta)
        // log(1 + x/k) asymptotes gently; k tunes initial stiffness.
        let friction = log(1 + magnitude / 18)
        return sign * min(max, friction * (max / log(1 + 120 / 18)))
    }
}
