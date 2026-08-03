import Foundation
import LifeOSCore

public struct MultiDayTaskPlan: Sendable, Equatable {
    public var parent: LifeTask
    public var slices: [LifeTask]
    public var project: CreativeProject?

    public init(parent: LifeTask, slices: [LifeTask], project: CreativeProject? = nil) {
        self.parent = parent
        self.slices = slices
        self.project = project
    }
}

/// Builds parent + slice tasks for a multi-day goal, scheduling each slice in the correct window.
public enum MultiDayTaskPlanner {
    private static let calendar = Calendar.current

    public static func plan(
        from draft: MultiDayPlanDraft,
        userId: String,
        existingTasks: [LifeTask] = [],
        profile: UserLifeProfile = UserLifeProfileStore.load(),
        startDate: Date = Date()
    ) -> MultiDayTaskPlan {
        let dayCount = clampedDayCount(draft.dayCount)
        let slices = normalizedSlices(from: draft, dayCount: dayCount)
        return buildPlan(
            title: draft.title,
            dayCount: dayCount,
            lifeArea: draft.lifeArea,
            deadline: draft.deadline,
            slices: slices,
            userId: userId,
            existingTasks: existingTasks,
            profile: profile,
            startDate: startDate
        )
    }

    public static func plan(
        title: String,
        dayCount: Int,
        lifeArea: LifeArea = .work,
        deadline: Date? = nil,
        userId: String,
        existingTasks: [LifeTask] = [],
        profile: UserLifeProfile = UserLifeProfileStore.load(),
        startDate: Date = Date()
    ) -> MultiDayTaskPlan {
        let clamped = clampedDayCount(dayCount)
        let slices = offlineSlices(title: title, dayCount: clamped, lifeArea: lifeArea, profile: profile)
        return buildPlan(
            title: title,
            dayCount: clamped,
            lifeArea: lifeArea,
            deadline: deadline,
            slices: slices,
            userId: userId,
            existingTasks: existingTasks,
            profile: profile,
            startDate: startDate
        )
    }

    // MARK: - Build

    private static func buildPlan(
        title: String,
        dayCount: Int,
        lifeArea: LifeArea,
        deadline: Date?,
        slices: [MultiDaySliceDraft],
        userId: String,
        existingTasks: [LifeTask],
        profile: UserLifeProfile,
        startDate: Date
    ) -> MultiDayTaskPlan {
        let parentId = UUID().uuidString
        let dayStart = calendar.startOfDay(for: startDate)

        var parent = LifeTask(
            title: title,
            lifeArea: lifeArea,
            priority: .medium,
            status: .pending,
            estimatedMinutes: slices.reduce(0) { $0 + $1.estimatedMinutes },
            userId: userId
        )
        parent.id = parentId
        parent.tags = [MultiDayTaskTags.root]
        parent.deadline = deadline
        parent.scheduledDate = nil
        parent.scheduledTime = nil

        let windowKind = SchedulingWindowSelector.windowKind(for: lifeArea)
        let workHours = SchedulingWindowSelector.workHours(for: windowKind, profile: profile)

        var scheduledSlices: [LifeTask] = []
        var pool = existingTasks

        for sliceDraft in slices.sorted(by: { $0.dayIndex < $1.dayIndex }) {
            guard let targetDay = calendar.date(byAdding: .day, value: sliceDraft.dayIndex, to: dayStart) else { continue }

            var slice = LifeTask(
                title: sliceDraft.title,
                lifeArea: lifeArea,
                priority: .medium,
                status: .pending,
                estimatedMinutes: max(sliceDraft.estimatedMinutes, TaskDurationPolicy.minimumMinutes),
                scheduledDate: targetDay,
                tags: [MultiDayTaskTags.slice],
                userId: userId
            )
            slice.id = UUID().uuidString
            slice.parentTaskId = parentId

            let dayTasks = pool.filter { task in
                guard let scheduledDate = task.scheduledDate else { return false }
                return calendar.isDate(scheduledDate, inSameDayAs: targetDay)
            }

            let request = DaySlotAllocator.Request(
                id: slice.id,
                estimatedMinutes: slice.estimatedMinutes,
                priority: .medium,
                preferredStart: nil
            )
            if let allocation = DaySlotAllocator.allocate(
                requests: [request],
                existingTasks: dayTasks,
                workHours: workHours,
                referenceDay: targetDay,
                now: startDate,
                calendar: calendar
            ).first {
                slice.scheduledTime = allocation.scheduledTime
                let duration = max(slice.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
                slice.scheduledEndTime = allocation.scheduledTime.addingTimeInterval(TimeInterval(duration * 60))
            }

            scheduledSlices.append(slice)
            pool.append(slice)
        }

        var project: CreativeProject?
        if lifeArea == .creativity {
            project = CreativeProject(
                title: title,
                medium: "Multi-day goal",
                status: "In Progress",
                progress: 0,
                dayCount: dayCount,
                deadline: deadline,
                parentTaskId: parentId,
                lifeArea: lifeArea,
                milestoneTaskIds: scheduledSlices.map(\.id)
            )
        }

        return MultiDayTaskPlan(parent: parent, slices: scheduledSlices, project: project)
    }

    private static func clampedDayCount(_ count: Int) -> Int {
        max(2, min(count, 90))
    }

    private static func normalizedSlices(from draft: MultiDayPlanDraft, dayCount: Int) -> [MultiDaySliceDraft] {
        if !draft.slices.isEmpty {
            return draft.slices
        }
        return offlineSlices(title: draft.title, dayCount: dayCount, lifeArea: draft.lifeArea)
    }

    static func offlineSlices(
        title: String,
        dayCount: Int,
        lifeArea: LifeArea,
        profile: UserLifeProfile = UserLifeProfileStore.load()
    ) -> [MultiDaySliceDraft] {
        let windowKind = SchedulingWindowSelector.windowKind(for: lifeArea)
        let label = SchedulingWindowSelector.windowLabel(for: windowKind, profile: profile)
        return (0..<dayCount).map { index in
            MultiDaySliceDraft(
                dayIndex: index,
                title: "Day \(index + 1): \(title)",
                estimatedMinutes: 45,
                windowLabel: label
            )
        }
    }
}
