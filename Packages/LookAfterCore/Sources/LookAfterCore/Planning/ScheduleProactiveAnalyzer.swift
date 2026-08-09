import Foundation

/// Proactive schedule suggestion surfaced before the user asks.
public struct ScheduleProactiveSuggestion: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case workOnRestDay
        case meetingOutsideOfficeHours
        case duplicateSeries
        case pastDueStillToday
        case fixedTaskMissingTime
        case longEveningGap
        case workAfterWindDown
        case overloadedAfternoon
        case preSleepCrunch
        case highFocusDuringLowEnergy
        case noBreaksInLongBlock
        case tooManyContextSwitches
        case initiationHeavyStack
        case protectedTimeConflict
        case medicationNotScheduled
        case sleepTargetDrift
        case morningPlanReview
        case middayCheckpoint
        case postCompletionMomentum
    }

    public enum Severity: String, Sendable, CaseIterable {
        case low
        case medium
        case high
    }

    public let id: String
    public let kind: Kind
    public let severity: Severity
    public let message: String
    public let options: [String]
    public let relatedTaskIDs: [String]

    public init(
        id: String = UUID().uuidString,
        kind: Kind,
        severity: Severity,
        message: String,
        options: [String],
        relatedTaskIDs: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.message = message
        self.options = options
        self.relatedTaskIDs = relatedTaskIDs
    }
}

/// Deterministic proactive planning detectors — schedule sanity, day shape, energy, life model.
public enum ScheduleProactiveAnalyzer {

    public struct Input: Sendable {
        public var tasks: [LifeTask]
        public var profile: UserLifeProfile
        public var lifeModel: LifeModel?
        public var referenceDate: Date
        public var now: Date
        public var energyPercent: Int
        public var completedTodayCount: Int
        public var calendar: Calendar

        public init(
            tasks: [LifeTask],
            profile: UserLifeProfile = UserLifeProfileStore.load(),
            lifeModel: LifeModel? = LifeModelStore.load(),
            referenceDate: Date = Date(),
            now: Date = Date(),
            energyPercent: Int = 55,
            completedTodayCount: Int = 0,
            calendar: Calendar = .current
        ) {
            self.tasks = tasks
            self.profile = profile
            self.lifeModel = lifeModel
            self.referenceDate = referenceDate
            self.now = now
            self.energyPercent = energyPercent
            self.completedTodayCount = completedTodayCount
            self.calendar = calendar
        }
    }

    public static func analyze(_ input: Input) -> [ScheduleProactiveSuggestion] {
        let dayStart = input.calendar.startOfDay(for: input.referenceDate)
        let activeToday = input.tasks.filter { task in
            guard task.status.isActive, !TaskRecurrenceEngine.isRecurrenceTemplate(task) else { return false }
            return TaskRecurrenceEngine.isActionableToday(
                task,
                in: input.tasks,
                calendar: input.calendar,
                referenceDate: input.referenceDate
            )
        }

        var suggestions: [ScheduleProactiveSuggestion] = []
        suggestions += tierAScheduleSanity(tasks: activeToday, allTasks: input.tasks, input: input, dayStart: dayStart)
        suggestions += tierBDayShape(tasks: activeToday, allTasks: input.tasks, input: input, dayStart: dayStart)
        suggestions += tierCEnergyADHD(tasks: activeToday, input: input, dayStart: dayStart)
        suggestions += tierDLifeModel(tasks: activeToday, allTasks: input.tasks, input: input, dayStart: dayStart)
        suggestions += tierEConversationStarters(input: input, activeCount: activeToday.count)

        return suggestions
            .sorted { severityRank($0.severity) > severityRank($1.severity) }
            .prefix(6)
            .map { $0 }
    }

    public static func topSuggestion(_ input: Input) -> ScheduleProactiveSuggestion? {
        analyze(input).first
    }

    // MARK: - Tier A

    private static func tierAScheduleSanity(
        tasks: [LifeTask],
        allTasks: [LifeTask],
        input: Input,
        dayStart: Date
    ) -> [ScheduleProactiveSuggestion] {
        var results: [ScheduleProactiveSuggestion] = []
        let isWeekend = input.calendar.isDateInWeekend(dayStart)
        let windows = SchedulingWindows.from(profile: input.profile, lifeModel: input.lifeModel)

        if isWeekend {
            for task in tasks where isWorkLike(task) && !TaskConstraintAlignment.isUserPlaced(task) {
                results.append(ScheduleProactiveSuggestion(
                    kind: .workOnRestDay,
                    severity: .high,
                    message: "\"\(task.title)\" on \(weekdayLabel(dayStart, calendar: input.calendar)) — is that intentional?",
                    options: ["Move to Monday", "Keep one-off", "Remove from today"],
                    relatedTaskIDs: [task.id]
                ))
                break
            }
        }

        for task in tasks where task.isFixedTimeEvent {
            guard let start = task.scheduledTime else { continue }
            let hour = input.calendar.component(.hour, from: start)
            if hour < windows.officeHours.startHour || hour >= windows.officeHours.endHour {
                results.append(ScheduleProactiveSuggestion(
                    kind: .meetingOutsideOfficeHours,
                    severity: .medium,
                    message: "\"\(task.title)\" at \(ScheduleTimeFormatting.timeLabel(start, calendar: input.calendar)) looks outside your usual office hours.",
                    options: ["Reschedule to office window", "Keep it"],
                    relatedTaskIDs: [task.id]
                ))
            }
        }

        let grouped = Dictionary(grouping: tasks.filter { $0.scheduledDate != nil }) {
            OnboardingTaskSeeder.normalizedRoutineTitle($0.title)
        }
        for (_, group) in grouped where group.count > 1 {
            results.append(ScheduleProactiveSuggestion(
                kind: .duplicateSeries,
                severity: .medium,
                message: "You have \(group.count) \"\(group[0].title)\" blocks today.",
                options: ["Merge duplicates", "Keep both"],
                relatedTaskIDs: group.map(\.id)
            ))
            break
        }

        for task in tasks {
            guard let start = task.scheduledTime, start < input.now, task.status.isActive else { continue }
            results.append(ScheduleProactiveSuggestion(
                kind: .pastDueStillToday,
                severity: .medium,
                message: "\"\(task.title)\" was due at \(ScheduleTimeFormatting.timeLabel(start, calendar: input.calendar)) — still doing it?",
                options: ["Reschedule", "Mark done", "Defer to tomorrow"],
                relatedTaskIDs: [task.id]
            ))
            break
        }

        for task in tasks where task.schedulingModeValue == .fixedTime && task.scheduledTime == nil {
            results.append(ScheduleProactiveSuggestion(
                kind: .fixedTaskMissingTime,
                severity: .low,
                message: "\"\(task.title)\" is fixed but has no time — want to pick one?",
                options: ["Pick a time", "Make flexible"],
                relatedTaskIDs: [task.id]
            ))
            break
        }

        return results
    }

    // MARK: - Tier B

    private static func tierBDayShape(
        tasks: [LifeTask],
        allTasks: [LifeTask],
        input: Input,
        dayStart: Date
    ) -> [ScheduleProactiveSuggestion] {
        var results: [ScheduleProactiveSuggestion] = []
        let boundaryContext = DayBoundaryPlanner.Context(
            profile: input.profile,
            tasks: allTasks,
            lifeModel: input.lifeModel
        )
        let dayEnd = DayBoundaryPlanner.actionableDayEnd(
            on: dayStart,
            now: input.now,
            calendar: input.calendar,
            context: boundaryContext
        )

        let scheduled = tasks
            .compactMap { task -> (LifeTask, Date, Date)? in
                guard let window = TaskScheduleInterval.window(for: task, on: dayStart, calendar: input.calendar) else { return nil }
                return (task, window.start, window.end)
            }
            .sorted { $0.1 < $1.1 }

        if let last = scheduled.last, last.1 >= eveningThreshold(on: dayStart, calendar: input.calendar) {
            let priorEnd = scheduled.dropLast().last?.2 ?? input.now
            let gapMinutes = Int(last.1.timeIntervalSince(max(priorEnd, input.now)) / 60)
            if gapMinutes >= 60 {
                results.append(ScheduleProactiveSuggestion(
                    kind: .longEveningGap,
                    severity: .high,
                    message: "You have about \(gapMinutes) minutes before \"\(last.0.title)\" — want to finish the day earlier?",
                    options: ["Move tasks earlier", "Defer late tasks to tomorrow", "Keep plan"],
                    relatedTaskIDs: [last.0.id]
                ))
            }
        }

        let afterWindDown = scheduled.filter { $0.1 >= dayEnd && $0.0.isSchedulerMovable }
        if !afterWindDown.isEmpty {
            results.append(ScheduleProactiveSuggestion(
                kind: .workAfterWindDown,
                severity: .medium,
                message: "\(afterWindDown.count) task(s) sit after your wind-down — move them to tomorrow?",
                options: ["Defer all", "Keep plan"],
                relatedTaskIDs: afterWindDown.map(\.0.id)
            ))
        }

        if let fit = PreWindowFitAnalyzer.analyze(tasks: allTasks, now: input.now, calendar: input.calendar),
           fit.isOvercommitted {
            results.append(ScheduleProactiveSuggestion(
                kind: .preSleepCrunch,
                severity: .high,
                message: fit.summaryLine,
                options: ["Replan afternoon", "Defer movable tasks", "End day early"],
                relatedTaskIDs: fit.skipTaskIDs
            ))
        }

        let afternoonMinutes = scheduled
            .filter { input.calendar.component(.hour, from: $0.1) >= 12 }
            .reduce(0) { $0 + Int($1.2.timeIntervalSince($1.1) / 60) }
        if afternoonMinutes > 240, scheduled.count >= 4 {
            results.append(ScheduleProactiveSuggestion(
                kind: .overloadedAfternoon,
                severity: .medium,
                message: "Your afternoon is packed — defer a couple of lower-priority items?",
                options: ["Show defer options", "Replan", "Keep plan"],
                relatedTaskIDs: scheduled.suffix(2).map(\.0.id)
            ))
        }

        return results
    }

    // MARK: - Tier C

    private static func tierCEnergyADHD(
        tasks: [LifeTask],
        input: Input,
        dayStart: Date
    ) -> [ScheduleProactiveSuggestion] {
        var results: [ScheduleProactiveSuggestion] = []
        let lowEnergy = input.energyPercent < 45

        if lowEnergy {
            for task in tasks {
                let semantic = task.semanticProfile?.semanticType ?? TaskSemanticProfileBuilder.build(from: task).semanticType
                guard semantic == .deepWork || semantic == .learning else { continue }
                guard let start = task.scheduledTime, input.calendar.isDate(start, inSameDayAs: dayStart) else { continue }
                let hour = input.calendar.component(.hour, from: start)
                if hour >= 14 {
                    results.append(ScheduleProactiveSuggestion(
                        kind: .highFocusDuringLowEnergy,
                        severity: .medium,
                        message: "Energy is low and \"\(task.title)\" is demanding — shift it earlier or defer?",
                        options: ["Move earlier", "Defer", "Keep it"],
                        relatedTaskIDs: [task.id]
                    ))
                    break
                }
            }
        }

        let windows = scheduledWindows(tasks: tasks, dayStart: dayStart, calendar: input.calendar)
        for window in windows where window.durationMinutes >= 180 {
            results.append(ScheduleProactiveSuggestion(
                kind: .noBreaksInLongBlock,
                severity: .low,
                message: "You have ~\(window.durationMinutes / 60)+ hours straight — add a 10-minute break?",
                options: ["Insert break", "Keep plan"]
            ))
            break
        }

        if contextSwitchCount(tasks: tasks) >= 4 {
            results.append(ScheduleProactiveSuggestion(
                kind: .tooManyContextSwitches,
                severity: .low,
                message: "Lots of switching today — batch similar tasks together?",
                options: ["Replan batch", "Keep plan"]
            ))
        }

        let hardStarts = tasks.filter {
            ($0.semanticProfile?.semanticType ?? .generic) == .deepWork || $0.difficulty == .hard
        }
        if hardStarts.count >= 3 {
            results.append(ScheduleProactiveSuggestion(
                kind: .initiationHeavyStack,
                severity: .medium,
                message: "Three hard starts in a row is a lot — spread them out?",
                options: ["Spread tasks", "Keep plan"],
                relatedTaskIDs: hardStarts.prefix(3).map(\.id)
            ))
        }

        return results
    }

    // MARK: - Tier D

    private static func tierDLifeModel(
        tasks: [LifeTask],
        allTasks: [LifeTask],
        input: Input,
        dayStart: Date
    ) -> [ScheduleProactiveSuggestion] {
        var results: [ScheduleProactiveSuggestion] = []
        guard let model = input.lifeModel else { return results }

        for block in model.timeBlocks {
            guard block.days.includes(dayStart, calendar: input.calendar) else { continue }
            guard let blockStart = input.calendar.date(
                bySettingHour: block.startHour,
                minute: block.startMinute,
                second: 0,
                of: dayStart
            ),
            let blockEnd = input.calendar.date(
                bySettingHour: block.endHour,
                minute: block.endMinute,
                second: 0,
                of: dayStart
            ) else { continue }
            let protected = TaskScheduleInterval(taskID: block.id, start: blockStart, end: blockEnd)

            for task in tasks {
                guard let taskWindow = TaskScheduleInterval.window(for: task, on: dayStart, calendar: input.calendar) else { continue }
                if taskWindow.overlaps(protected) {
                    results.append(ScheduleProactiveSuggestion(
                        kind: .protectedTimeConflict,
                        severity: .high,
                        message: "\"\(task.title)\" overlaps your \(block.label) block.",
                        options: ["Move task", "Keep plan"],
                        relatedTaskIDs: [task.id]
                    ))
                    break
                }
            }
        }

        let meds = MedicationStore.load().filter { !$0.isTaken && !$0.name.isEmpty }
        if !meds.isEmpty {
            let medTitles = Set(allTasks.map { $0.title.lowercased() })
            if !meds.contains(where: { medTitles.contains($0.name.lowercased()) }) {
                results.append(ScheduleProactiveSuggestion(
                    kind: .medicationNotScheduled,
                    severity: .medium,
                    message: "No medication reminder on today's plan — add one?",
                    options: ["Add reminder", "Already taken"]
                ))
            }
        }

        let boundaryContext = DayBoundaryPlanner.Context(profile: input.profile, tasks: allTasks, lifeModel: model)
        let dayEnd = DayBoundaryPlanner.actionableDayEnd(
            on: dayStart,
            now: input.now,
            calendar: input.calendar,
            context: boundaryContext
        )
        if let latestEnd = tasks.compactMap({ TaskScheduleInterval.window(for: $0, on: dayStart, calendar: input.calendar)?.end }).max(),
           latestEnd > dayEnd.addingTimeInterval(45 * 60) {
            results.append(ScheduleProactiveSuggestion(
                kind: .sleepTargetDrift,
                severity: .medium,
                message: "Your plan runs past your sleep target — trim the day or extend bedtime?",
                options: ["Trim day", "Keep plan"]
            ))
        }

        return results
    }

    // MARK: - Tier E

    private static func tierEConversationStarters(input: Input, activeCount: Int) -> [ScheduleProactiveSuggestion] {
        var results: [ScheduleProactiveSuggestion] = []
        let hour = input.calendar.component(.hour, from: input.now)
        let dayProgress = Double(hour) / 24.0

        if hour < 10, activeCount > 0 {
            results.append(ScheduleProactiveSuggestion(
                kind: .morningPlanReview,
                severity: .low,
                message: "Want to walk through today's plan together?",
                options: ["Review plan", "Not now"]
            ))
        }

        if dayProgress >= 0.5, input.completedTodayCount < max(1, activeCount / 3) {
            results.append(ScheduleProactiveSuggestion(
                kind: .middayCheckpoint,
                severity: .low,
                message: "You're behind pace — replan the afternoon?",
                options: ["Replan afternoon", "Keep going"]
            ))
        }

        if input.completedTodayCount >= 3 {
            results.append(ScheduleProactiveSuggestion(
                kind: .postCompletionMomentum,
                severity: .low,
                message: "Nice streak — tackle one more or call it a win?",
                options: ["One more task", "Stop for now"]
            ))
        }

        return results
    }

    // MARK: - Helpers

    private static func severityRank(_ severity: ScheduleProactiveSuggestion.Severity) -> Int {
        switch severity {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        }
    }

    private static func isWorkLike(_ task: LifeTask) -> Bool {
        if task.lifeArea == .work { return true }
        let title = task.title.lowercased()
        let keywords = ["office", "work", "standup", "stand-up", "commute", "meeting", "sync"]
        return keywords.contains(where: { title.contains($0) })
    }

    private static func weekdayLabel(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private static func eveningThreshold(on dayStart: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: 20, minute: 0, second: 0, of: dayStart) ?? dayStart
    }

    private struct ScheduledWindow {
        var durationMinutes: Int
    }

    private static func scheduledWindows(tasks: [LifeTask], dayStart: Date, calendar: Calendar) -> [ScheduledWindow] {
        let intervals = TaskScheduleInterval.intervals(from: tasks, on: dayStart, calendar: calendar).sorted { $0.start < $1.start }
        guard !intervals.isEmpty else { return [] }
        var merged: [TaskScheduleInterval] = []
        var current = intervals[0]
        for interval in intervals.dropFirst() {
            if interval.start <= current.end.addingTimeInterval(15 * 60) {
                current = TaskScheduleInterval(
                    taskID: current.taskID,
                    start: current.start,
                    end: max(current.end, interval.end)
                )
            } else {
                merged.append(current)
                current = interval
            }
        }
        merged.append(current)
        return merged.map {
            ScheduledWindow(durationMinutes: Int($0.end.timeIntervalSince($0.start) / 60))
        }
    }

    private static func contextSwitchCount(tasks: [LifeTask]) -> Int {
        let ordered = tasks
            .compactMap { task -> (Date, LifeArea)? in
                guard let start = task.scheduledTime else { return nil }
                return (start, task.lifeArea)
            }
            .sorted { $0.0 < $1.0 }
        guard ordered.count >= 2 else { return 0 }
        var switches = 0
        for index in 1..<ordered.count where ordered[index].1 != ordered[index - 1].1 {
            switches += 1
        }
        return switches
    }
}
