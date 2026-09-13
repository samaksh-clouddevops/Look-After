import Foundation

/// Represents the major life domains that LifeOS organizes around.
/// Every task, inbox item, and memory entry belongs to one or more life areas.
public enum LifeArea: String, Codable, CaseIterable, Identifiable, Sendable {
    case work = "Work"
    case health = "Health & Recovery"
    case relationships = "Relationships"
    case finance = "Finance & Bills"
    case home = "Home Management"
    case creativity = "Music & Creativity"
    case learning = "Learning & Knowledge"
    case shopping = "Shopping & Inventory"
    case travel = "Travel"
    case medication = "Medication"
    case hydration = "Hydration & Nutrition"
    case reflection = "Reflection & Journaling"
    case personal = "Personal"
    
    public var id: String { rawValue }

    /// Compact label for dense chips (priority rows, filters) — avoids truncating long raw values.
    public var shortLabel: String {
        switch self {
        case .health: return "Health"
        case .finance: return "Finance"
        case .home: return "Home"
        case .creativity: return "Creative"
        case .learning: return "Learning"
        case .shopping: return "Shopping"
        case .hydration: return "Nutrition"
        case .reflection: return "Journal"
        case .work, .relationships, .travel, .medication, .personal:
            return rawValue
        }
    }
    
    public var icon: String {
        switch self {
        case .work: return "briefcase.fill"
        case .health: return "heart.fill"
        case .relationships: return "person.2.fill"
        case .finance: return "dollarsign.circle.fill"
        case .home: return "house.fill"
        case .creativity: return "music.note"
        case .learning: return "book.fill"
        case .shopping: return "cart.fill"
        case .travel: return "airplane"
        case .medication: return "pills.fill"
        case .hydration: return "drop.fill"
        case .reflection: return "pencil.and.scribble"
        case .personal: return "person.fill"
        }
    }
    
    public var accentColorHex: String {
        "A5ABB5"
    }
}

/// Sub-category for `.work` tasks only — lets the user distinguish a meeting from
/// a general work task, call, or email instead of every fixed-time Work item being
/// treated as a meeting on the timeline.
public enum WorkTaskCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case task = "Task"
    case meeting = "Meeting"
    case call = "Call"
    case email = "Email"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .task: return "checklist"
        case .meeting: return "calendar"
        case .call: return "phone.fill"
        case .email: return "envelope.fill"
        }
    }

    public var timelineKind: LifeTimelineEventKind {
        switch self {
        case .task: return .work
        case .meeting: return .meeting
        case .call, .email: return .work
        }
    }
}
