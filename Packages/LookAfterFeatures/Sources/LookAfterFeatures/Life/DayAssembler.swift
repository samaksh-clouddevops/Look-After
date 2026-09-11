import Foundation
import LookAfterCore

/// Builds today's tasks from compiled life commitments — the brain maintains the day.
public enum DayAssembler {

    public struct Result: Sendable {
        public var tasksToCreate: [LifeTask]
        public var skippedTitles: [String]

        public init(tasksToCreate: [LifeTask] = [], skippedTitles: [String] = []) {
            self.tasksToCreate = tasksToCreate
            self.skippedTitles = skippedTitles
        }
    }

    public static func assemble(
        model: LifeModel,
        existingTasks: [LifeTask],
        completedToday: [LifeTask],
        userId: String,
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> Result {
        guard model.hasContent, !userId.isEmpty else { return Result() }

        var toCreate: [LifeTask] = []
        var skipped: [String] = []
        let all = existingTasks + completedToday
        let dayStart = calendar.startOfDay(for: date)

        let primaryCreative = primaryCreativeCommitment(
            model: model,
            existingTasks: existingTasks,
            completedToday: completedToday,
            date: date,
            calendar: calendar
        )

        for commitment in model.commitments {
            guard commitment.frequency.applies(on: date, calendar: calendar) else { continue }

            if commitment.lifeArea == .creativity,
               let primaryCreative,
               commitment.id != primaryCreative.id {
                skipped.append(commitment.title)
                continue
            }

            let tag = model.commitmentID(for: commitment.title)
            let seriesKey = "recurring|\(OnboardingTaskSeeder.normalizedRoutineTitle(commitment.title))"
            let alreadyExists = all.contains { task in
                let onDay = task.scheduledDate.map { calendar.isDate($0, inSameDayAs: dayStart) } ?? false
                if task.tags.contains(tag), onDay || task.scheduledDate == nil {
                    return task.status.isActive || task.status == .completed || onDay
                }
                if TaskScheduleQuery.seriesKey(for: task) == seriesKey,
                   task.status.isActive || task.status == .completed,
                   onDay {
                    return true
                }
                if normalized(task.title) == normalized(commitment.title) {
                    if onDay { return true }
                    // Unscheduled commitment row still counts — avoid Gym/Dinner twins.
                    if task.tags.contains(LifeModel.commitmentTaskTag),
                       task.status.isActive || task.status == .completed {
                        return true
                    }
                }
                return false
            }

            if alreadyExists {
                skipped.append(commitment.title)
                continue
            }

            if hasMultiDaySlice(for: commitment.lifeArea, on: date, in: all, calendar: calendar) {
                skipped.append(commitment.title)
                continue
            }

            if let task = makeTask(
                for: commitment,
                model: model,
                userId: userId,
                date: date,
                dayStart: dayStart,
                calendar: calendar,
                existingTasks: all
            ) {
                toCreate.append(task)
            }
        }

        return Result(tasksToCreate: toCreate, skippedTitles: skipped)
    }

    /// Picks the highest-priority creative commitment not yet represented today.
    public static func primaryCreativeCommitment(
        model: LifeModel,
        existingTasks: [LifeTask],
        completedToday: [LifeTask],
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> LifeCommitment? {
        let all = existingTasks + completedToday
        let creative = model.commitments
            .filter { $0.lifeArea == .creativity }
            .sorted { $0.priority < $1.priority }

        for commitment in creative where commitment.frequency.applies(on: date, calendar: calendar) {
            let tag = model.commitmentID(for: commitment.title)
            let doneOrScheduled = all.contains {
                $0.tags.contains(tag) || normalized($0.title) == normalized(commitment.title)
            }
            if !doneOrScheduled {
                return commitment
            }
        }
        return creative.first
    }

    // MARK: - Task building

    private static func makeTask(
        for commitment: LifeCommitment,
        model: LifeModel,
        userId: String,
        date: Date,
        dayStart: Date,
        calendar: Calendar,
        existingTasks: [LifeTask]
    ) -> LifeTask? {
        let block = resolvedBlock(for: commitment, model: model)

        guard let block else { return makeFlexibleCommitmentTask(commitment, model: model, userId: userId, date: dayStart) }

        let startHour = block.startHour
        let startMinute = block.startMinute
        guard let start = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: dayStart) else {
            return nil
        }

        let endMinutes = block.startMinutesFromMidnight + commitment.defaultMinutes
        let endHour = endMinutes / 60
        let endMinute = endMinutes % 60
        let end: Date?
        if endHour >= 24 {
            end = start.addingTimeInterval(TimeInterval(commitment.defaultMinutes * 60))
        } else {
            end = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: dayStart)
        }

        // Block-backed commitments are fixed anchors — AI must not reschedule them.
        let isFixed = commitment.isNonNegotiable
            || block.protection == .neverSchedule
            || block.protection == .priorityOnly
        let tag = model.commitmentID(for: commitment.title)

        var task = LifeTask(
            title: commitment.title,
            description: "Life commitment from your profile",
            lifeArea: commitment.lifeArea,
            priority: commitment.isNonNegotiable ? .high : .medium,
            difficulty: .medium,
            estimatedMinutes: commitment.defaultMinutes,
            scheduledDate: dayStart,
            scheduledTime: start,
            tags: [LifeModel.commitmentTaskTag, tag],
            recurrence: nil,
            schedulingMode: isFixed ? .fixedTime : .flexible,
            scheduledEndTime: end
        )
        task.userId = userId
        return task
    }

    /// Prefer the commitment's own block. Never fall back to gym or creative for the wrong life area.
    private static func resolvedBlock(for commitment: LifeCommitment, model: LifeModel) -> ProtectedTimeBlock? {
        if let label = commitment.preferredBlockLabel, let block = model.block(matching: label) {
            return block
        }

        let title = commitment.title.lowercased()
        if commitment.lifeArea == .health || title.contains("gym") || title.contains("workout") || title.contains("exercise") {
            return model.timeBlocks.first { $0.label.lowercased().contains("gym") }
        }
        if commitment.lifeArea == .creativity {
            return model.creativeBlocks().first
        }
        if commitment.lifeArea == .work {
            return model.timeBlocks.first { block in
                let label = block.label.lowercased()
                return label.contains("office") || label.contains("work")
            }
        }
        return nil
    }

    private static func makeFlexibleCommitmentTask(
        _ commitment: LifeCommitment,
        model: LifeModel,
        userId: String,
        date: Date
    ) -> LifeTask {
        let tag = model.commitmentID(for: commitment.title)
        var task = LifeTask(
            title: commitment.title,
            description: "Life commitment from your profile",
            lifeArea: commitment.lifeArea,
            priority: .medium,
            difficulty: .medium,
            estimatedMinutes: commitment.defaultMinutes,
            scheduledDate: date,
            tags: [LifeModel.commitmentTaskTag, tag],
            recurrence: nil,
            schedulingMode: .flexible
        )
        task.userId = userId
        return task
    }

    private static func normalized(_ title: String) -> String {
        title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hasMultiDaySlice(
        for lifeArea: LifeArea,
        on date: Date,
        in tasks: [LifeTask],
        calendar: Calendar
    ) -> Bool {
        tasks.contains { task in
            guard MultiDayTaskTags.isSlice(task) else { return false }
            guard task.lifeArea == lifeArea else { return false }
            guard let scheduled = task.scheduledDate else { return false }
            return calendar.isDate(scheduled, inSameDayAs: date)
        }
    }
}
