import Foundation

/// Display payload for the pinned NOW Live Activity — aligned with execution layer + Flow Director.
public struct PinNowDisplayModel: Codable, Sendable, Equatable {
    public var headline: String
    public var contextLine: String
    public var scheduleLabel: String
    public var constraintLabel: String
    public var categoryIcon: String
    public var nextUpSummary: String
    public var energyScore: Int
    public var energyLevel: String
    public var estimatedMinutes: Int
    public var progressFraction: Double
    public var sectionLabel: String
    /// When set, the Live Activity widget can render live countdown/progress without app updates.
    public var windowStart: Date?
    public var windowEnd: Date?

    public init(
        headline: String,
        contextLine: String,
        scheduleLabel: String,
        constraintLabel: String,
        categoryIcon: String,
        nextUpSummary: String,
        energyScore: Int,
        energyLevel: String,
        estimatedMinutes: Int,
        progressFraction: Double,
        sectionLabel: String,
        windowStart: Date? = nil,
        windowEnd: Date? = nil
    ) {
        self.headline = headline
        self.contextLine = contextLine
        self.scheduleLabel = scheduleLabel
        self.constraintLabel = constraintLabel
        self.categoryIcon = categoryIcon
        self.nextUpSummary = nextUpSummary
        self.energyScore = energyScore
        self.energyLevel = energyLevel
        self.estimatedMinutes = estimatedMinutes
        self.progressFraction = min(1, max(0, progressFraction))
        self.sectionLabel = sectionLabel
        self.windowStart = windowStart
        self.windowEnd = windowEnd
    }
}

/// Builds pin display data from schedule resolution + Flow Surface hero.
public enum PinNowSnapshotBuilder {

    public static func build(
        tasks: [LifeTask],
        flowSurface: FlowSurface?,
        cognitiveSnapshot: CognitiveSnapshot?,
        preferredTask: LifeTask? = nil,
        timelineEvents: [LifeTimelineEvent]? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PinNowDisplayModel? {
        let activeTasks = tasks.filter(\.status.isActive)
        guard !activeTasks.isEmpty else { return nil }

        let execution = ExecutionBlockResolver.resolve(tasks: tasks, now: now, calendar: calendar)

        if let events = timelineEvents, !events.isEmpty,
           let nowEvent = TimelineNowResolver.currentNowEvent(in: events, now: now, calendar: calendar),
           let model = buildFromTimelineNowEvent(
               nowEvent,
               tasks: tasks,
               execution: execution,
               flowSurface: flowSurface,
               cognitiveSnapshot: cognitiveSnapshot,
               calendar: calendar,
               now: now
           ) {
            return model
        }

        let hero = resolvePreferredTask(
            preferredTask: preferredTask,
            flowSurface: flowSurface,
            activeTasks: activeTasks,
            tasks: tasks
        )

        if let hero {
            let heroTask = tasks.first(where: { $0.id == hero.id }) ?? hero
            if heroTask.status.isActive {
                if execution.taskID == heroTask.id,
                   execution.surfaceMode != .idle,
                   execution.surfaceMode != .fluidGap,
                   let model = buildFromExecutionBlock(
                       execution: execution,
                       task: heroTask,
                       flowSurface: flowSurface,
                       cognitiveSnapshot: cognitiveSnapshot,
                       calendar: calendar
                   ) {
                    return model
                }
                if ExecutionBlockResolver.isInActiveWindow(heroTask, now: now, calendar: calendar)
                    || !heroTask.isLifeCommitmentTask,
                   let model = buildFromTask(
                       task: heroTask,
                       execution: execution,
                       flowSurface: flowSurface,
                       cognitiveSnapshot: cognitiveSnapshot,
                       calendar: calendar,
                       sectionLabel: nil
                   ) {
                    return model
                }
            }
        }

        if let taskID = execution.taskID,
           execution.surfaceMode != .idle,
           execution.surfaceMode != .fluidGap,
           let executionTask = tasks.first(where: { $0.id == taskID }) {
            if let model = buildFromExecutionBlock(
                execution: execution,
                task: executionTask,
                flowSurface: flowSurface,
                cognitiveSnapshot: cognitiveSnapshot,
                calendar: calendar
            ) {
                return model
            }
        }

        if let upcoming = activeTasks.first(where: { task in
            guard let day = task.scheduledDate ?? task.scheduledTime else { return false }
            let taskDay = calendar.startOfDay(for: day)
            let today = calendar.startOfDay(for: now)
            guard taskDay == today else { return false }
            if let start = TaskScheduleInterval.resolvedStart(for: task, on: today, calendar: calendar) {
                return start > now
            }
            return false
        }),
        let model = buildFromTask(
            task: upcoming,
            execution: execution,
            flowSurface: flowSurface,
            cognitiveSnapshot: cognitiveSnapshot,
            calendar: calendar,
            sectionLabel: "Next up"
        ) {
            return model
        }

        for task in activeTasks {
            if let model = buildFromTask(
                task: task,
                execution: execution,
                flowSurface: flowSurface,
                cognitiveSnapshot: cognitiveSnapshot,
                calendar: calendar,
                sectionLabel: nil
            ) {
                return model
            }
        }

        return nil
    }

    // MARK: - Timeline NOW (matches Today timeline marker)

    private static func buildFromTimelineNowEvent(
        _ event: LifeTimelineEvent,
        tasks: [LifeTask],
        execution: ExecutionBlockSnapshot,
        flowSurface: FlowSurface?,
        cognitiveSnapshot: CognitiveSnapshot?,
        calendar: Calendar,
        now: Date
    ) -> PinNowDisplayModel? {
        if let taskID = TimelineNowResolver.taskId(from: event.id),
           let task = tasks.first(where: { $0.id == taskID }) {
            if execution.taskID == task.id,
               execution.surfaceMode != .idle,
               execution.surfaceMode != .fluidGap,
               let model = buildFromExecutionBlock(
                   execution: execution,
                   task: task,
                   flowSurface: flowSurface,
                   cognitiveSnapshot: cognitiveSnapshot,
                   calendar: calendar,
                   sectionLabelOverride: "NOW"
               ) {
                return model
            }
            if let model = buildFromTask(
                task: task,
                execution: execution,
                flowSurface: flowSurface,
                cognitiveSnapshot: cognitiveSnapshot,
                calendar: calendar,
                sectionLabel: "NOW"
            ) {
                return model
            }
        }

        return buildFromTimelineEventOnly(
            event,
            tasks: tasks,
            execution: execution,
            flowSurface: flowSurface,
            cognitiveSnapshot: cognitiveSnapshot,
            calendar: calendar,
            now: now
        )
    }

    private static func buildFromTimelineEventOnly(
        _ event: LifeTimelineEvent,
        tasks: [LifeTask],
        execution: ExecutionBlockSnapshot,
        flowSurface: FlowSurface?,
        cognitiveSnapshot: CognitiveSnapshot?,
        calendar: Calendar,
        now: Date
    ) -> PinNowDisplayModel? {
        let headline = sanitized(event.title)
        guard !headline.isEmpty else { return nil }

        let end = event.resolvedEndDate(calendar: calendar)
        let totalMinutes = max(1, Int(end.timeIntervalSince(event.date) / 60))
        let scheduleLabel = event.isFlexibleToday
            ? "Flexible • \(compactDuration(minutes: totalMinutes))"
            : ScheduleTimeFormatting.rangeLabel(from: event.date, to: end, calendar: calendar)

        let elapsed = max(0, now.timeIntervalSince(event.date))
        let progress = min(1, elapsed / end.timeIntervalSince(event.date))

        let category = categoryForTimelineEvent(event, tasks: tasks)

        return PinNowDisplayModel(
            headline: headline,
            contextLine: contextLineForTimelineEvent(event, flowSurface: flowSurface, cognitiveSnapshot: cognitiveSnapshot),
            scheduleLabel: scheduleLabel,
            constraintLabel: constraintLabel(for: event.resolvedTimeConstraint),
            categoryIcon: category.systemImage,
            nextUpSummary: execution.nextUpSummary,
            energyScore: energyScore(from: flowSurface, cognitiveSnapshot: cognitiveSnapshot),
            energyLevel: cognitiveSnapshot?.energy.rawValue ?? EnergyLevel.moderate.rawValue,
            estimatedMinutes: max(1, Int(end.timeIntervalSince(now) / 60)),
            progressFraction: progress,
            sectionLabel: "NOW",
            windowStart: event.date,
            windowEnd: end
        )
    }

    private static func categoryForTimelineEvent(
        _ event: LifeTimelineEvent,
        tasks: [LifeTask]
    ) -> FocusTaskCategory {
        if let taskID = TimelineNowResolver.taskId(from: event.id),
           let task = tasks.first(where: { $0.id == taskID }) {
            return FocusTaskCategory.resolve(for: task)
        }
        switch event.kind {
        case .work, .meeting: return .deepWork
        case .health, .medication, .exercise: return .health
        case .recovery: return .recovery
        case .creative: return .creative
        case .relationship, .personal, .travel, .habit: return .social
        case .finance, .bill, .shopping: return .admin
        }
    }

    private static func constraintLabel(for constraint: TimeConstraint) -> String {
        switch constraint {
        case .anchored: return "Anchored"
        case .flexible: return "Flexible"
        case .fluid: return "Fluid"
        }
    }

    private static func contextLineForTimelineEvent(
        _ event: LifeTimelineEvent,
        flowSurface: FlowSurface?,
        cognitiveSnapshot: CognitiveSnapshot?
    ) -> String {
        if let taskID = TimelineNowResolver.taskId(from: event.id),
           let prediction = flowSurface?.prediction,
           prediction.taskID == taskID,
           !prediction.reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return truncate(UserFacingCopy.sanitize(prediction.reasoning))
        }

        let subtitle = sanitized(event.subtitle)
        if !subtitle.isEmpty,
           subtitle != "Planned",
           subtitle != "Done",
           subtitle != "Window passed" {
            return truncate(subtitle)
        }

        if let energy = cognitiveSnapshot?.energy {
            return truncate(energy.description)
        }

        return "Your current block on today's timeline."
    }

    private static func resolvePreferredTask(
        preferredTask: LifeTask?,
        flowSurface: FlowSurface?,
        activeTasks: [LifeTask],
        tasks: [LifeTask]
    ) -> LifeTask? {
        let candidates = [preferredTask, flowSurface?.heroTask].compactMap { $0 }
        for candidate in candidates {
            if activeTasks.contains(where: { $0.id == candidate.id }) {
                return candidate
            }
            if let match = tasks.first(where: { $0.id == candidate.id }), match.status.isActive {
                return match
            }
        }
        return nil
    }

    // MARK: - Execution block (primary)

    private static func buildFromExecutionBlock(
        execution: ExecutionBlockSnapshot,
        task: LifeTask,
        flowSurface: FlowSurface?,
        cognitiveSnapshot: CognitiveSnapshot?,
        calendar: Calendar,
        sectionLabelOverride: String? = nil
    ) -> PinNowDisplayModel? {
        let headline = displayTitle(for: task, executionFallback: execution.taskTitle)
        guard !headline.isEmpty else { return nil }

        let totalMinutes = max(1, Int(execution.windowEnd.timeIntervalSince(execution.windowStart) / 60))
        let remainingMinutes = max(1, Int(execution.remainingSeconds / 60))
        let scheduleLabel = scheduleLabelForWindow(
            start: execution.windowStart,
            end: execution.windowEnd,
            totalMinutes: totalMinutes,
            calendar: calendar
        )

        return PinNowDisplayModel(
            headline: headline,
            contextLine: contextLine(
                for: task,
                execution: execution,
                flowSurface: flowSurface,
                cognitiveSnapshot: cognitiveSnapshot,
                usesExecutionContext: true
            ),
            scheduleLabel: scheduleLabel,
            constraintLabel: execution.constraintLabel,
            categoryIcon: execution.category.systemImage,
            nextUpSummary: execution.nextUpSummary,
            energyScore: energyScore(from: flowSurface, cognitiveSnapshot: cognitiveSnapshot),
            energyLevel: cognitiveSnapshot?.energy.rawValue ?? EnergyLevel.moderate.rawValue,
            estimatedMinutes: remainingMinutes,
            progressFraction: execution.progressFraction,
            sectionLabel: sectionLabelOverride ?? sectionLabel(for: execution),
            windowStart: execution.windowStart,
            windowEnd: execution.windowEnd
        )
    }

    // MARK: - Task fallback

    private static func buildFromTask(
        task: LifeTask,
        execution: ExecutionBlockSnapshot,
        flowSurface: FlowSurface?,
        cognitiveSnapshot: CognitiveSnapshot?,
        calendar: Calendar,
        sectionLabel: String?
    ) -> PinNowDisplayModel? {
        let headline = displayTitle(for: task, executionFallback: nil)
        guard !headline.isEmpty else { return nil }

        let category = FocusTaskCategory.resolve(for: task)
        let day = calendar.startOfDay(for: Date())
        let taskWindow = TaskScheduleInterval.window(for: task, on: day, calendar: calendar)
        let flowWindow = flowSurface?.flowWindow

        let scheduleLabel: String
        let estimatedMinutes: Int
        var windowStart: Date?
        var windowEnd: Date?
        if let window = taskWindow {
            let totalMinutes = max(1, Int(window.end.timeIntervalSince(window.start) / 60))
            scheduleLabel = scheduleLabelForWindow(
                start: window.start,
                end: window.end,
                totalMinutes: totalMinutes,
                calendar: calendar
            )
            estimatedMinutes = totalMinutes
            windowStart = window.start
            windowEnd = window.end
        } else if let flowWindow, flowWindow.end > flowWindow.start {
            let totalMinutes = max(1, Int(flowWindow.duration / 60))
            scheduleLabel = scheduleLabelForWindow(
                start: flowWindow.start,
                end: flowWindow.end,
                totalMinutes: totalMinutes,
                calendar: calendar
            )
            estimatedMinutes = totalMinutes
            windowStart = flowWindow.start
            windowEnd = flowWindow.end
        } else {
            let minutes = flowSurface?.prediction?.suggestedDurationMinutes ?? task.estimatedMinutes
            estimatedMinutes = max(1, minutes)
            scheduleLabel = "\(task.timeConstraintValue == .anchored ? "Anchored" : "Flexible") • \(compactDuration(minutes: estimatedMinutes))"
        }

        return PinNowDisplayModel(
            headline: headline,
            contextLine: contextLine(
                for: task,
                execution: execution,
                flowSurface: flowSurface,
                cognitiveSnapshot: cognitiveSnapshot,
                usesExecutionContext: false
            ),
            scheduleLabel: scheduleLabel,
            constraintLabel: constraintLabel(for: task),
            categoryIcon: category.systemImage,
            nextUpSummary: execution.nextUpSummary,
            energyScore: energyScore(from: flowSurface, cognitiveSnapshot: cognitiveSnapshot),
            energyLevel: cognitiveSnapshot?.energy.rawValue ?? EnergyLevel.moderate.rawValue,
            estimatedMinutes: estimatedMinutes,
            progressFraction: 0,
            sectionLabel: sectionLabel ?? category.displayName,
            windowStart: windowStart,
            windowEnd: windowEnd
        )
    }

    // MARK: - Field builders

    private static func displayTitle(for task: LifeTask, executionFallback: String?) -> String {
        let sanitizedTitle = sanitized(task.title)
        if !sanitizedTitle.isEmpty, !UserFacingCopy.isInternalExecutionLabel(sanitizedTitle) {
            return sanitizedTitle
        }

        let headline = sanitized(HumanLanguage.outcomeHeadline(task: task))
        if !headline.isEmpty, !UserFacingCopy.isInternalExecutionLabel(headline) {
            return headline
        }

        if let subtype = task.semanticProfile?.subtype, !subtype.isEmpty {
            let subtypeTitle = sanitized(subtype)
            if !subtypeTitle.isEmpty { return subtypeTitle }
        }

        if let executionFallback {
            let fallback = sanitized(executionFallback)
            if !fallback.isEmpty, fallback != "Fluid Gap" {
                return fallback
            }
        }

        return sanitizedTitle
    }

    private static func scheduleLabelForWindow(
        start: Date,
        end: Date,
        totalMinutes: Int,
        calendar: Calendar
    ) -> String {
        ScheduleTimeFormatting.rangeLabel(from: start, to: end, calendar: calendar)
    }

    private static func constraintLabel(for task: LifeTask) -> String {
        switch task.timeConstraintValue {
        case .anchored: return "Anchored"
        case .flexible: return "Flexible"
        case .fluid: return "Fluid"
        }
    }

    private static func sectionLabel(for execution: ExecutionBlockSnapshot) -> String {
        switch execution.surfaceMode {
        case .recovery: return "Recovery"
        case .fluidGap: return "Next up"
        case .idle: return "NOW"
        case .anchored, .flexible: return execution.category.displayName
        }
    }

    private static func contextLine(
        for task: LifeTask,
        execution: ExecutionBlockSnapshot,
        flowSurface: FlowSurface?,
        cognitiveSnapshot: CognitiveSnapshot?,
        usesExecutionContext: Bool
    ) -> String {
        if let prediction = flowSurface?.prediction,
           prediction.taskID == task.id {
            if !prediction.reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return truncate(UserFacingCopy.sanitize(prediction.reasoning))
            }
            if !prediction.buttonSubtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return truncate(UserFacingCopy.sanitize(prediction.buttonSubtitle))
            }
        }

        if usesExecutionContext, !execution.nextUpSummary.isEmpty {
            return truncate(execution.nextUpSummary)
        }

        if execution.surfaceMode == .fluidGap, !execution.nextUpSummary.isEmpty {
            return truncate(execution.nextUpSummary)
        }

        let description = sanitized(task.description)
        if !description.isEmpty,
           !description.lowercased().contains("life commitment from your profile") {
            return truncate(description)
        }

        if let energy = cognitiveSnapshot?.energy {
            return truncate(energy.description)
        }

        if task.timeConstraintValue == .anchored {
            return "Fixed window — stay in this block."
        }

        return "Ready when you are."
    }

    private static func energyScore(
        from flowSurface: FlowSurface?,
        cognitiveSnapshot: CognitiveSnapshot?
    ) -> Int {
        let raw = flowSurface?.energyScore ?? cognitiveSnapshot?.energyScore ?? 0.5
        return Int(min(100, max(0, raw * 100)))
    }

    public static func compactDuration(minutes: Int) -> String {
        let clamped = max(1, minutes)
        if clamped >= 60 {
            let hours = clamped / 60
            let mins = clamped % 60
            if mins == 0 { return "\(hours)h" }
            return "\(hours)h \(mins)m"
        }
        return "\(clamped)m"
    }

    private static func sanitized(_ text: String) -> String {
        UserFacingCopy.sanitize(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncate(_ text: String, max length: Int = 72) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > length else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: length)
        return String(trimmed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
