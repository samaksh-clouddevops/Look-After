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
                if task.tags.contains(tag) { return true }
                let onDay = task.scheduledDate.map { calendar.isDate($0, inSameDayAs: dayStart) } ?? true
                if TaskScheduleQuery.seriesKey(for: task) == seriesKey,
                   task.status.isActive || task.status == .completed,
                   onDay {
                    return true
                }
                return normalized(task.title) == normalized(commitment.title)
                    && task.scheduledDate.map { calendar.isDate($0, inSameDayAs: date) } == true
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
        let block = commitment.preferredBlockLabel.flatMap { model.block(matching: $0) }
            ?? model.creativeBlocks().first
            ?? model.timeBlocks.first { $0.label.lowercased().contains("gym") }

        guard let block else { return makeFlexibleCommitmentTask(commitment, model: model, userId: userId, date: dayStart) }

        let startHour = block.startHour
        let startMinute = block.startMinute
        guard let start = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: dayStart) else {
            return nil
        }

        let endMinutes = block.startMinutesFromMidnight + commitment.defaultMinutes
        let endHour = endMinutes / 60
        let endMinute = endMinutes % 60
        let end = calendar.date(bySettingHour: min(endHour, 23), minute: endMinute, second: 0, of: dayStart)

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
