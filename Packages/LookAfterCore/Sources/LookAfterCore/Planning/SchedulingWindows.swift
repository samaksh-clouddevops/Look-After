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

    public func overlapsProtected(start: Date, end: Date, calendar: Calendar = .current) -> Bool {
        let startMinutes = calendar.component(.hour, from: start) * 60 + calendar.component(.minute, from: start)
        let endMinutes = calendar.component(.hour, from: end) * 60 + calendar.component(.minute, from: end)
        return protectedBlocks.contains { block in
            guard block.days.includes(start, calendar: calendar) else { return false }
            return startMinutes < block.endMinutesFromMidnight && block.startMinutesFromMidnight < endMinutes
        }
    }

    public func protectedIntervals(on day: Date, calendar: Calendar = .current) -> [TaskScheduleInterval] {
        let dayStart = calendar.startOfDay(for: day)
        return protectedBlocks.compactMap { block in
            guard block.days.includes(dayStart, calendar: calendar) else { return nil }
            guard let start = calendar.date(
                bySettingHour: block.startHour,
                minute: block.startMinute,
                second: 0,
                of: dayStart
            ) else { return nil }
            let end = calendar.date(
                bySettingHour: block.endHour,
                minute: block.endMinute,
                second: 0,
                of: dayStart
            ) ?? start.addingTimeInterval(3600)
            guard end > start else { return nil }
            return TaskScheduleInterval(taskID: "protected.\(block.id)", start: start, end: end)
        }
    }
}
