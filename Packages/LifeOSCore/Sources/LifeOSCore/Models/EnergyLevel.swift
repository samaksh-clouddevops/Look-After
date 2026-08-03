import Foundation

/// Represents the user's current energy level, used for energy-aware task scheduling.
public enum EnergyLevel: String, Codable, CaseIterable, Identifiable, Sendable, Comparable {
    case peak = "Peak"
    case high = "High"
    case moderate = "Moderate"
    case low = "Low"
    case recovery = "Recovery"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .peak: return "bolt.fill"
        case .high: return "bolt"
        case .moderate: return "minus.circle"
        case .low: return "battery.25"
        case .recovery: return "bed.double.fill"
        }
    }
    
    public var numericValue: Double {
        switch self {
        case .peak: return 1.0
        case .high: return 0.75
        case .moderate: return 0.5
        case .low: return 0.25
        case .recovery: return 0.1
        }
    }
    
    public var colorHex: String {
        switch self {
        case .peak: return "F4F5F6"
        case .high: return "C8CDD6"
        case .moderate: return "A5ABB5"
        case .low: return "7A808A"
        case .recovery: return "5C6169"
        }
    }
    
    public var description: String {
        switch self {
        case .peak: return "You're at peak energy — tackle your hardest task"
        case .high: return "Good energy — great time for meaningful work"
        case .moderate: return "Moderate energy — handle routine tasks"
        case .low: return "Low energy — stick to easy, quick wins"
        case .recovery: return "Recovery mode — rest and recharge"
        }
    }
    
    // MARK: - Comparable
    
    private var sortOrder: Int {
        switch self {
        case .recovery: return 0
        case .low: return 1
        case .moderate: return 2
        case .high: return 3
        case .peak: return 4
        }
    }
    
    public static func < (lhs: EnergyLevel, rhs: EnergyLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

/// Represents the difficulty/cognitive load of a task.
public enum TaskDifficulty: String, Codable, CaseIterable, Identifiable, Sendable {
    case trivial = "Trivial"
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
    case intense = "Intense"
    
    public var id: String { rawValue }
    
    /// The minimum energy level recommended to attempt this task.
    public var minimumEnergy: EnergyLevel {
        switch self {
        case .trivial: return .recovery
        case .easy: return .low
        case .medium: return .moderate
        case .hard: return .high
        case .intense: return .peak
        }
    }
    
    public var estimatedMinutes: ClosedRange<Int> {
        switch self {
        case .trivial: return 1...5
        case .easy: return 5...15
        case .medium: return 15...45
        case .hard: return 45...120
        case .intense: return 120...240
        }
    }
}

/// Priority level for tasks.
public enum Priority: Int, Codable, CaseIterable, Identifiable, Sendable, Comparable {
    case critical = 4
    case high = 3
    case medium = 2
    case low = 1
    case someday = 0
    
    public var id: Int { rawValue }
    
    public var label: String {
        switch self {
        case .critical: return "Critical"
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        case .someday: return "Someday"
        }
    }
    
    public var icon: String {
        switch self {
        case .critical: return "exclamationmark.triangle.fill"
        case .high: return "arrow.up.circle.fill"
        case .medium: return "minus.circle.fill"
        case .low: return "arrow.down.circle.fill"
        case .someday: return "cloud.fill"
        }
    }
    
    public var colorHex: String {
        switch self {
        case .critical: return "F4F5F6"
        case .high: return "C8CDD6"
        case .medium: return "A5ABB5"
        case .low: return "7A808A"
        case .someday: return "5C6169"
        }
    }
    
    public static func < (lhs: Priority, rhs: Priority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static func fromLLM(_ raw: String) -> Priority? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "critical", "urgent": return .critical
        case "high": return .high
        case "medium", "normal": return .medium
        case "low": return .low
        case "someday": return .someday
        default: return nil
        }
    }
}
