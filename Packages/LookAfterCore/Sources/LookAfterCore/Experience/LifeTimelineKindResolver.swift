import Foundation

/// Maps tasks to stable timeline categories — hygiene/meals never flip between Personal and Recovery.
public enum LifeTimelineKindResolver {

    public static func kind(for task: LifeTask) -> LifeTimelineEventKind {
        // Explicit user choice wins — Work tasks are only "meeting" if the user marked them as such.
        if task.lifeArea == .work, let workCategory = task.workCategory {
            return workCategory.timelineKind
        }

        let profile = TaskSemanticProfileBuilder.classificationProfile(for: task)
        let base = kind(for: profile, task: task)

        // No explicit sub-category set — fall back to the previous heuristic (fixed-time Work ⇒ meeting)
        // for tasks created before this feature existed.
        if task.isFixedTimeEvent, base == .work {
            return .meeting
        }
        return base
    }

    // MARK: - Private

    private static func kind(for profile: TaskSemanticProfile, task: LifeTask) -> LifeTimelineEventKind {
        switch profile.semanticType {
        case .medication:
            return .medication
        case .physicalActivity:
            return .exercise
        case .selfCare:
            return .habit
        case .errand:
            return profile.subtype == "meal" ? .health : .shopping
        case .creative:
            return .creative
        case .communication:
            return .work
        case .learning:
            return .personal
        case .deepWork, .administrative, .generic:
            break
        }

        let lower = task.title.lowercased()
        if lower.contains("gym") || lower.contains("workout") || lower.contains("yoga") || lower.contains("run") {
            return .exercise
        }

        switch task.lifeArea {
        case .work: return .work
        case .health: return .health
        case .finance: return .finance
        case .shopping: return .shopping
        case .travel: return .travel
        case .medication: return .medication
        case .creativity: return .creative
        case .personal, .reflection, .home, .learning: return .personal
        case .relationships: return .relationship
        case .hydration: return .health
        }
    }
}
