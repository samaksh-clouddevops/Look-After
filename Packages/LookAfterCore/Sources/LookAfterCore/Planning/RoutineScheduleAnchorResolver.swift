import Foundation

/// Resolves when daily routines, meals, and profile-backed blocks should occur.
public enum RoutineScheduleAnchorResolver {

    public struct ResolvedAnchor: Sendable, Equatable {
        public let start: Date
        public let end: Date
        /// When true the task should be snapped to this window instead of blind sequential slotting.
        public let treatAsFixed: Bool

        public init(start: Date, end: Date, treatAsFixed: Bool) {
            self.start = start
            self.end = end
            self.treatAsFixed = treatAsFixed
        }
    }

    public static func resolve(
        for task: LifeTask,
        on day: Date,
        model: LifeModel? = LifeModelStore.load(),
        profile: UserLifeProfile = UserLifeProfileStore.load(),
        calendar: Calendar = .current
    ) -> ResolvedAnchor? {
        let dayStart = calendar.startOfDay(for: day)
        let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
        let enriched = TaskEphemeralityDefaults.enrich(task)
        let title = task.title.lowercased()

        // Life-model blocks first so gym stays at the user's evening slot, not a seeder default.
        if let commitmentAnchor = commitmentBlockAnchor(
            for: task,
            model: model,
            day: dayStart,
            durationMinutes: duration,
            calendar: calendar
        ) {
            return commitmentAnchor
        }

        if let blockAnchor = matchingTimeBlockAnchor(
            for: task,
            model: model,
            day: dayStart,
            durationMinutes: duration,
            calendar: calendar
        ) {
            return blockAnchor
        }

        if let keywordAnchor = keywordBlockAnchor(
            for: task,
            model: model,
            day: dayStart,
            durationMinutes: duration,
            calendar: calendar
        ) {
            return keywordAnchor
        }

        if !profile.fixedScheduleNotes.isEmpty,
           let fixed = OnboardingTaskSeeder.fixedTimeAnchor(
            matchingTitle: task.title,
            fixedNotes: profile.fixedScheduleNotes,
            on: day,
            calendar: calendar
           ) {
            let end = fixed.start.addingTimeInterval(TimeInterval(fixed.durationMinutes * 60))
            return ResolvedAnchor(start: fixed.start, end: end, treatAsFixed: true)
        }

        if let routine = OnboardingTaskSeeder.routineAnchorTime(forTitle: task.title, on: day, calendar: calendar) {
            let end = routine.start.addingTimeInterval(TimeInterval(routine.durationMinutes * 60))
            // Meals yield on conflict. Gym / workouts keep their evening clock.
            let treatAsFixed = !OnboardingTaskSeeder.isMealRoutineTitle(task.title)
            return ResolvedAnchor(start: routine.start, end: end, treatAsFixed: treatAsFixed)
        }

        let windows = SchedulingWindows.from(profile: profile, lifeModel: model)

        if title.contains("commute") {
            let officeStart = calendar.date(
                bySettingHour: windows.officeHours.startHour,
                minute: windows.officeHours.startMinute,
                second: 0,
                of: dayStart
            ) ?? dayStart
            let start = calendar.date(byAdding: .minute, value: -duration, to: officeStart) ?? officeStart
            let clamped = max(start, dayStart)
            return ResolvedAnchor(
                start: clamped,
                end: clamped.addingTimeInterval(TimeInterval(duration * 60)),
                treatAsFixed: false
            )
        }

        if title.contains("standup") || title.contains("stand-up") {
            let start = calendar.date(
                bySettingHour: windows.officeHours.startHour,
                minute: min(windows.officeHours.startMinute + 5, 59),
                second: 0,
                of: dayStart
            ) ?? dayStart
            return ResolvedAnchor(
                start: start,
                end: start.addingTimeInterval(TimeInterval(duration * 60)),
                treatAsFixed: false
            )
        }

        if title.contains("office") && title.contains("work") {
            let start = calendar.date(
                bySettingHour: windows.officeHours.startHour,
                minute: windows.officeHours.startMinute,
                second: 0,
                of: dayStart
            ) ?? dayStart
            return ResolvedAnchor(
                start: start,
                end: start.addingTimeInterval(TimeInterval(duration * 60)),
                treatAsFixed: false
            )
        }

        if let box = enriched.temporalBoundingBox,
           let start = calendar.date(bySettingHour: box.earliestStartHour, minute: 0, second: 0, of: dayStart) {
            let end = start.addingTimeInterval(TimeInterval(duration * 60))
            return ResolvedAnchor(start: start, end: end, treatAsFixed: task.tags.contains("daily-routine"))
        }

        return nil
    }

    /// True when a task's current placement violates its anchor or meal bounding box.
    public static func shouldRestore(
        task: LifeTask,
        anchor: ResolvedAnchor,
        calendar: Calendar = .current
    ) -> Bool {
        if TaskConstraintAlignment.isUserPlaced(task) { return false }
        if TaskScheduleInterval.isPlaceholderMidnightSchedule(for: task, calendar: calendar) {
            return true
        }
        guard let current = task.scheduledTime else { return true }

        let enriched = TaskEphemeralityDefaults.enrich(task)
        if let box = enriched.temporalBoundingBox, !box.contains(start: current, calendar: calendar) {
            return true
        }

        // Meals often sit inside a wide evening fence after a bad `now` park — snap to anchor.
        if OnboardingTaskSeeder.isMealRoutineTitle(task.title) {
            return abs(current.timeIntervalSince(anchor.start)) > 20 * 60
        }

        if anchor.treatAsFixed {
            let delta = abs(current.timeIntervalSince(anchor.start))
            return delta > 15 * 60
        }

        let title = task.title.lowercased()
        if title.contains("commute")
            || title.contains("standup")
            || title.contains("stand-up")
            || (title.contains("office") && title.contains("work")) {
            return abs(current.timeIntervalSince(anchor.start)) > 60 * 60
        }

        return false
    }

    public static func preferredStart(
        for task: LifeTask,
        on day: Date,
        model: LifeModel? = LifeModelStore.load(),
        profile: UserLifeProfile = UserLifeProfileStore.load(),
        calendar: Calendar = .current
    ) -> Date? {
        resolve(for: task, on: day, model: model, profile: profile, calendar: calendar)?.start
    }

    // MARK: - Life model

    private static func commitmentBlockAnchor(
        for task: LifeTask,
        model: LifeModel?,
        day: Date,
        durationMinutes: Int,
        calendar: Calendar
    ) -> ResolvedAnchor? {
        guard let model else { return nil }
        guard task.isLifeCommitmentTask || task.tags.contains(LifeModel.commitmentTaskTag) else { return nil }

        guard let commitment = model.commitments.first(where: {
            task.tags.contains(model.commitmentID(for: $0.title))
                || titlesMatch(task.title, $0.title)
        }) else { return nil }

        guard let blockLabel = commitment.preferredBlockLabel,
              let block = model.block(matching: blockLabel),
              block.days.includes(day, calendar: calendar) else { return nil }

        guard let start = calendar.date(
            bySettingHour: block.startHour,
            minute: block.startMinute,
            second: 0,
            of: day
        ) else { return nil }

        let endMinutes = block.startMinutesFromMidnight + commitment.defaultMinutes
        let end = calendar.date(
            bySettingHour: min(endMinutes / 60, 23),
            minute: endMinutes % 60,
            second: 0,
            of: day
        ) ?? start.addingTimeInterval(TimeInterval(durationMinutes * 60))

        let isRigid = commitment.isNonNegotiable
            || block.protection == .neverSchedule
            || block.protection == .priorityOnly
        return ResolvedAnchor(start: start, end: end, treatAsFixed: isRigid)
    }

    private static func keywordBlockAnchor(
        for task: LifeTask,
        model: LifeModel?,
        day: Date,
        durationMinutes: Int,
        calendar: Calendar
    ) -> ResolvedAnchor? {
        guard let model else { return nil }
        let title = normalize(task.title)

        let gymKeywords = ["gym", "workout", "exercise", "lift", "training"]
        if gymKeywords.contains(where: { title.contains($0) }) {
            if let anchor = anchorForBlock(
                labels: ["gym", "exercise", "workout", "fitness"],
                model: model,
                day: day,
                durationMinutes: durationMinutes,
                calendar: calendar,
                rigid: true
            ) {
                return anchor
            }
            if let commitment = model.commitments.first(where: {
                normalize($0.title).contains("gym") || normalize($0.title).contains("workout")
            }) {
                return commitmentBlockAnchor(
                    for: task,
                    model: model,
                    day: day,
                    durationMinutes: max(durationMinutes, commitment.defaultMinutes),
                    calendar: calendar
                )
            }
        }

        let creativeKeywords = ["vocal", "music", "creative", "practice", "art", "studio"]
        if creativeKeywords.contains(where: { title.contains($0) }) {
            if let anchor = anchorForBlock(
                labels: ["creative", "music", "deep work", "studio", "art"],
                model: model,
                day: day,
                durationMinutes: durationMinutes,
                calendar: calendar,
                rigid: task.isLifeCommitmentTask || task.tags.contains(LifeModel.commitmentTaskTag)
            ) {
                return anchor
            }
        }

        return nil
    }

    private static func anchorForBlock(
        labels: [String],
        model: LifeModel,
        day: Date,
        durationMinutes: Int,
        calendar: Calendar,
        rigid: Bool
    ) -> ResolvedAnchor? {
        guard let block = model.timeBlocks.first(where: { block in
            guard block.days.includes(day, calendar: calendar) else { return false }
            let label = normalize(block.label)
            return labels.contains(where: { label.contains($0) || $0.contains(label) })
        }) else { return nil }

        guard let start = calendar.date(
            bySettingHour: block.startHour,
            minute: block.startMinute,
            second: 0,
            of: day
        ) else { return nil }

        let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        let isRigid = rigid || block.protection == .neverSchedule || block.protection == .priorityOnly
        return ResolvedAnchor(start: start, end: end, treatAsFixed: isRigid)
    }

    private static func matchingTimeBlockAnchor(
        for task: LifeTask,
        model: LifeModel?,
        day: Date,
        durationMinutes: Int,
        calendar: Calendar
    ) -> ResolvedAnchor? {
        guard let model else { return nil }
        let normalizedTitle = normalize(task.title)

        guard let block = model.timeBlocks.first(where: { block in
            let label = normalize(block.label)
            return label == normalizedTitle
                || normalizedTitle.contains(label)
                || label.contains(normalizedTitle)
        }), block.days.includes(day, calendar: calendar) else { return nil }

        guard let start = calendar.date(
            bySettingHour: block.startHour,
            minute: block.startMinute,
            second: 0,
            of: day
        ) else { return nil }

        let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        let isRigid = block.protection == .neverSchedule || block.protection == .priorityOnly
        return ResolvedAnchor(start: start, end: end, treatAsFixed: isRigid)
    }

    private static func titlesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalize(lhs)
        let right = normalize(rhs)
        return left == right || left.contains(right) || right.contains(left)
    }

    private static func normalize(_ title: String) -> String {
        title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
