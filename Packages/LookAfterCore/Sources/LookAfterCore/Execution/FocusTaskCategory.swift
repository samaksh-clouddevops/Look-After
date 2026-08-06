import Foundation

/// Workspace category broadcast to Focus Filters and Live Activities.
/// Distinct from `LifeArea` — maps execution intent onto system Focus behavior.
public enum FocusTaskCategory: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case deepWork
    case recovery
    case admin
    case health
    case creative
    case social
    case fluidGap

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .deepWork: return "Deep Focus"
        case .recovery: return "Recovery"
        case .admin: return "Admin"
        case .health: return "Health"
        case .creative: return "Creative"
        case .social: return "Social"
        case .fluidGap: return "Fluid Gap"
        }
    }

    /// SF Symbol projected onto Dynamic Island leading compact.
    public var systemImage: String {
        switch self {
        case .deepWork: return "brain.head.profile"
        case .recovery: return "figure.mind.and.body"
        case .admin: return "tray.full.fill"
        case .health: return "heart.fill"
        case .creative: return "paintbrush.pointed.fill"
        case .social: return "person.2.fill"
        case .fluidGap: return "hourglass"
        }
    }

    /// Whether this category should request a restrictive system Focus Filter.
    public var requestsFocusFilter: Bool {
        switch self {
        case .deepWork, .creative, .health, .admin:
            return true
        case .recovery, .social, .fluidGap:
            return false
        }
    }

    /// Prefer suppression of low-priority notifications while active.
    public var suppressesLowPriorityNotifications: Bool {
        switch self {
        case .deepWork, .creative, .health:
            return true
        case .admin, .recovery, .social, .fluidGap:
            return false
        }
    }

    public static func resolve(for task: LifeTask) -> FocusTaskCategory {
        let lowered = (task.title + " " + task.tags.joined(separator: " ")).lowercased()
        if task.tags.contains(where: { $0.lowercased().contains("recovery") })
            || lowered.contains("recovery")
            || lowered.contains("breathing")
            || lowered.contains("sabotage") {
            return .recovery
        }

        let profile = TaskSemanticProfileBuilder.classificationProfile(for: task)
        switch profile.semanticType {
        case .deepWork, .learning:
            return .deepWork
        case .selfCare:
            return .recovery
        case .physicalActivity, .medication:
            return .health
        case .administrative, .errand:
            return .admin
        case .creative:
            return .creative
        case .communication:
            return .social
        case .generic:
            break
        }

        switch LifeTimelineKindResolver.kind(for: task) {
        case .recovery:
            return .recovery
        case .health, .medication, .exercise:
            return .health
        case .work, .meeting:
            return .deepWork
        case .creative:
            return .creative
        case .relationship:
            return .social
        case .personal, .habit, .finance, .bill, .shopping, .travel:
            return .admin
        }
    }
}
