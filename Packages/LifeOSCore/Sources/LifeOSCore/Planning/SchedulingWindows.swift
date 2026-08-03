import Foundation

/// Scheduling domains derived from the compiled life model.
public struct SchedulingWindows: Sendable, Equatable {
    public var officeHours: PlanningSchedulePolicy.WorkHours
    public var protectedBlocks: [ProtectedTimeBlock]
    public var creativeWindows: [PlanningSchedulePolicy.WorkHours]

    public init(
        officeHours: PlanningSchedulePolicy.WorkHours,
        protectedBlocks: [ProtectedTimeBlock] = [],
        creativeWindows: [PlanningSchedulePolicy.WorkHours] = []
    ) {
        self.officeHours = officeHours
        self.protectedBlocks = protectedBlocks
        self.creativeWindows = creativeWindows
    }

    public static func from(profile: UserLifeProfile, lifeModel: LifeModel? = LifeModelStore.load()) -> SchedulingWindows {
        if let lifeModel, lifeModel.hasContent {
            return from(lifeModel: lifeModel, profile: profile)
        }
        return SchedulingWindows(
            officeHours: PlanningSchedulePolicy.WorkHours.from(profile: profile),
            protectedBlocks: [],
            creativeWindows: []
        )
    }

    public static func from(lifeModel: LifeModel, profile: UserLifeProfile) -> SchedulingWindows {
        let office = lifeModel.timeBlocks.first(where: {
            let lower = $0.label.lowercased()
            return lower.contains("office") || lower.contains("work")
        })

        let officeHours = office?.asWorkHours() ?? PlanningSchedulePolicy.WorkHours.from(profile: profile)
        let protected = lifeModel.timeBlocks.filter { $0.protection == .neverSchedule || $0.protection == .priorityOnly }
        let creative = lifeModel.creativeBlocks().map { $0.asWorkHours() }

        return SchedulingWindows(
            officeHours: officeHours,
            protectedBlocks: protected,
            creativeWindows: creative
        )
    }

    public var allSchedulingWindows: [PlanningSchedulePolicy.WorkHours] {
        var windows = [officeHours]
        windows.append(contentsOf: creativeWindows)
        return windows
    }

    public func contains(minutesFromMidnight: Int) -> Bool {
        allSchedulingWindows.contains { window in
            minutesFromMidnight >= window.startMinutesFromMidnight
                && minutesFromMidnight <= window.endMinutesFromMidnight
        }
    }

    public func isProtected(minutesFromMidnight: Int) -> Bool {
        protectedBlocks.contains { block in
            minutesFromMidnight >= block.startMinutesFromMidnight
                && minutesFromMidnight < block.endMinutesFromMidnight
        }
    }
}
