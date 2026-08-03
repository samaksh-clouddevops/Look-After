import Foundation

/// Chooses scheduling windows for multi-day slice tasks based on life area and semantics.
public enum SchedulingWindowSelector {

    public enum WindowKind: Sendable, Equatable {
        case office
        case creative
        case gym
        case flexible
    }

    public static func windowKind(for lifeArea: LifeArea, semanticType: TaskSemanticType? = nil) -> WindowKind {
        if let semanticType {
            switch semanticType {
            case .creative: return .creative
            case .physicalActivity: return .gym
            case .deepWork, .administrative: return .office
            case .learning: return .office
            default: break
            }
        }

        switch lifeArea {
        case .creativity: return .creative
        case .health: return .gym
        case .work, .learning, .finance, .home: return .office
        default: return .flexible
        }
    }

    public static func workHours(
        for kind: WindowKind,
        profile: UserLifeProfile,
        lifeModel: LifeModel? = LifeModelStore.load()
    ) -> PlanningSchedulePolicy.WorkHours {
        let windows = SchedulingWindows.from(profile: profile, lifeModel: lifeModel)
        switch kind {
        case .office:
            return windows.officeHours
        case .creative:
            return windows.creativeWindows.first ?? windows.officeHours
        case .gym:
            if let model = lifeModel,
               let gym = model.timeBlocks.first(where: { $0.label.lowercased().contains("gym") }) {
                return gym.asWorkHours()
            }
            return windows.officeHours
        case .flexible:
            return windows.creativeWindows.first ?? windows.officeHours
        }
    }

    public static func preferredWindows(
        for lifeArea: LifeArea,
        profile: UserLifeProfile
    ) -> [PlanningSchedulePolicy.WorkHours] {
        let windows = SchedulingWindows.from(profile: profile)
        let kind = windowKind(for: lifeArea)
        switch kind {
        case .office:
            var result = [windows.officeHours]
            result.append(contentsOf: windows.creativeWindows)
            return result
        case .creative:
            if windows.creativeWindows.isEmpty {
                return [windows.officeHours]
            }
            return windows.creativeWindows
        case .gym, .flexible:
            return [workHours(for: kind, profile: profile)]
        }
    }

    public static func windowLabel(for kind: WindowKind, profile: UserLifeProfile) -> String {
        switch kind {
        case .office: return "Office"
        case .creative: return "Creative Deep Work"
        case .gym: return "Gym"
        case .flexible: return "Flexible"
        }
    }
}
