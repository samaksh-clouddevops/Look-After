import Foundation
import SwiftUI
import LifeOSCore

/// View model for the Executive Planning Conversation on Today.
@MainActor
public final class ExecutivePlanningViewModel: ObservableObject {
    @Published public private(set) var turns: [PlanningConversationTurn] = []
    @Published public private(set) var thinkingSteps: [String] = []
    @Published public private(set) var visibleThinkingStep: String?
    @Published public private(set) var isProcessing = false
    @Published public private(set) var inputMode: PlanningInputMode?
    @Published public private(set) var negotiation: PlanningNegotiation?
    @Published public private(set) var multiDayDraft: MultiDayPlanDraft?
    @Published public private(set) var multiDayPlanning: PlanningNegotiation?
    @Published public private(set) var multiDaySession: MultiDayPlanningSession?
    @Published public private(set) var timelineRows: [ExecutivePlanningTimelineRow] = []
    @Published public private(set) var tomorrowTimelineRows: [ExecutivePlanningTimelineRow] = []
    @Published public private(set) var recentDeltas: [PlanningTimelineDelta] = []
    @Published public var draftText = ""
    @Published public var errorMessage: String?

    @Published public private(set) var replanSummary: String?
    @Published public private(set) var isReplanning = false
    @Published public private(set) var isRedesigningWithAI = false

    public var onSpeakReply: ((String) -> Void)?

    private let engine: ExecutivePlanningEngine
    private let replanEngine = DayReplanEngine()
    private let applier = PlanMutationApplier()
    private var medications: [Medication] = []

    public init(engine: ExecutivePlanningEngine = ExecutivePlanningEngine()) {
        self.engine = engine
    }

    /// Wipes planning conversation and timeline UI state.
    public func factoryReset() {
        turns = []
        thinkingSteps = []
        visibleThinkingStep = nil
        isProcessing = false
        inputMode = nil
        negotiation = nil
        multiDayDraft = nil
        multiDayPlanning = nil
        multiDaySession = nil
        timelineRows = []
        tomorrowTimelineRows = []
        recentDeltas = []
        draftText = ""
        errorMessage = nil
        replanSummary = nil
        isReplanning = false
        isRedesigningWithAI = false
        medications = []
    }

    public func bootstrapTimeline(from events: [LifeTimelineEvent], now: Date = Date()) {
        guard timelineRows.isEmpty else { return }
        timelineRows = Self.rows(from: events, now: now)
    }

    public func refreshTimeline(from events: [LifeTimelineEvent], now: Date = Date()) {
        recentDeltas = []
        let built = Self.rows(from: events, now: now)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            timelineRows = built
        }
    }

    public func bootstrapTomorrowTimeline(from events: [LifeTimelineEvent]) {
        guard tomorrowTimelineRows.isEmpty else { return }
        tomorrowTimelineRows = Self.previewRows(from: events)
    }

    public func refreshTomorrowTimeline(from events: [LifeTimelineEvent]) {
        let built = Self.previewRows(from: events)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            tomorrowTimelineRows = built
        }
    }

    /// Instant timeline feedback when the user completes a task from the live timeline.
    public func markTimelineTaskCompleted(taskId: String) {
        guard let index = timelineRows.firstIndex(where: { $0.taskId == taskId && !$0.isCompleted }) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            timelineRows[index].isCompleted = true
            timelineRows[index].isNow = false
            timelineRows[index].isPast = false
            timelineRows[index].subtitle = "Done"
            timelineRows[index].completedAt = Date()
        }
    }

    /// Instant timeline feedback when a task is rescheduled from the live timeline.
    public func markTimelineTaskRescheduled(taskId: String, to newTime: Date) {
        guard let index = timelineRows.firstIndex(where: { $0.taskId == taskId }) else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            timelineRows[index].sortDate = newTime
            timelineRows[index].timeLabel = formatter.string(from: newTime)
            if let minutes = timelineRows[index].estimatedMinutes {
                let end = newTime.addingTimeInterval(TimeInterval(minutes * 60))
                timelineRows[index].endTimeLabel = formatter.string(from: end)
                timelineRows[index].scheduleRangeLabel = ScheduleTimeFormatting.rangeLabel(from: newTime, to: end)
            }
            timelineRows[index].isPast = false
            timelineRows[index].isNow = false
            timelineRows[index].change = .moved
        }
    }

    public func replanDay(
        context: DayReplanContext,
        tasksVM: TasksViewModel,
        modulesVM: LifeModulesViewModel,
        userId: String,
        refreshContext: @escaping () async -> Void
    ) async {
        isReplanning = true
        replanSummary = nil
        negotiation = nil
        isProcessing = true
        visibleThinkingStep = "Reconsidering the rest of your day"

        let analysis = PlanningReasoningPipeline.analyze(message: "Replan my day", context: context.planningContext)
        await animateThinking(steps: analysis.thinkingSteps)

        do {
            let result = try await replanEngine.replan(context: context)
            await applyReplanResult(result, tasksVM: tasksVM, modulesVM: modulesVM, userId: userId, refreshContext: refreshContext)

            replanSummary = result.summary
            turns.append(PlanningConversationTurn(role: .assistant, text: result.summary))
            recentDeltas = result.timelineDeltas

            if inputMode == .voice {
                onSpeakReply?(result.summary)
            }
        } catch {
            errorMessage = error.localizedDescription
            turns.append(PlanningConversationTurn(role: .assistant, text: "I couldn't replan right now — your current schedule is unchanged."))
        }

        isReplanning = false
        isProcessing = false
        visibleThinkingStep = nil
    }

    private func applyReplanResult(
        _ result: DayReplanResult,
        tasksVM: TasksViewModel,
        modulesVM: LifeModulesViewModel,
        userId: String,
        refreshContext: () async -> Void
    ) async {
        let calendar = Calendar.current
        let taskByID = Dictionary(uniqueKeysWithValues: tasksVM.tasks.map { ($0.id, $0) })
        let workHours = PlanningSchedulePolicy.WorkHours.from(profile: UserLifeProfileStore.load())

        for suggestion in result.scheduleChanges {
            guard var task = taskByID[suggestion.taskID], !task.isFixedTimeEvent else { continue }
            if suggestion.deferToTomorrow {
                task.scheduledDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
                task.scheduledTime = nil
            } else if let hour = suggestion.startHour, let minute = suggestion.startMinute,
                      let time = PlanningSchedulePolicy.validatedSchedule(
                        hour: hour,
                        minute: minute,
                        workHours: workHours
                      ) {
                task.scheduledDate = calendar.startOfDay(for: Date())
                task.scheduledTime = time
            }
            tasksVM.updateTask(task)
        }

        if !result.mutations.isEmpty {
            var meds = MedicationStore.load()
            _ = await applier.apply(
                mutations: result.mutations,
                tasksVM: tasksVM,
                modulesVM: modulesVM,
                userId: userId,
                medications: &meds,
                lifeProfile: UserLifeProfileStore.load()
            )
        }

        await refreshContext()
    }

    private func appendApplyNotices(
        to reply: String,
        applyResult: PlanMutationApplier.ApplyResult
    ) -> String {
        guard !applyResult.reusedTasks.isEmpty else { return reply }
        let notices = applyResult.reusedTasks.map {
            "I kept your existing task \"\($0.existingTitle)\" instead of creating \"\($0.requestedTitle)\" again."
        }
        if reply.isEmpty {
            return notices.joined(separator: " ")
        }
        return reply + "\n\n" + notices.joined(separator: " ")
    }

    public func submit(
        text: String,
        startedWithVoice: Bool,
        context: PlanningConversationContext,
        tasksVM: TasksViewModel,
        modulesVM: LifeModulesViewModel,
        userId: String,
        refreshContext: @escaping () async -> Void
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if inputMode == nil {
            inputMode = startedWithVoice ? .voice : .text
        }

        draftText = ""
        errorMessage = nil
        negotiation = nil
        multiDayPlanning = nil
        turns.append(PlanningConversationTurn(role: .user, text: trimmed))
        await processPlanningTurn(
            message: trimmed,
            context: context,
            tasksVM: tasksVM,
            modulesVM: modulesVM,
            userId: userId,
            refreshContext: refreshContext,
            forceAI: false
        )
    }

    /// Re-runs the same user message through the AI planner after an offline fallback.
    public func redesignWithAI(
        userMessage: String,
        context: PlanningConversationContext,
        tasksVM: TasksViewModel,
        modulesVM: LifeModulesViewModel,
        userId: String,
        refreshContext: @escaping () async -> Void
    ) async {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let last = turns.last, last.role == .assistant, last.responseSource == .offline {
            turns.removeLast()
        }

        errorMessage = nil
        negotiation = nil
        isRedesigningWithAI = true
        defer { isRedesigningWithAI = false }

        await processPlanningTurn(
            message: trimmed,
            context: context,
            tasksVM: tasksVM,
            modulesVM: modulesVM,
            userId: userId,
            refreshContext: refreshContext,
            forceAI: true
        )
    }

    private func processPlanningTurn(
        message: String,
        context: PlanningConversationContext,
        tasksVM: TasksViewModel,
        modulesVM: LifeModulesViewModel,
        userId: String,
        refreshContext: @escaping () async -> Void,
        forceAI: Bool
    ) async {
        isProcessing = true
        thinkingSteps = []
        visibleThinkingStep = nil

        medications = context.medications

        let analysis = PlanningReasoningPipeline.analyze(message: message, context: context)
        await animateThinking(steps: Array(analysis.thinkingSteps.prefix(3)))

        do {
            let response = try await engine.processTurn(
                message: message,
                context: context,
                history: turns,
                preAnalysis: analysis,
                forceAI: forceAI
            )

            let extraSteps = response.thinkingSteps.filter { !analysis.thinkingSteps.contains($0) }
            if !extraSteps.isEmpty {
                await animateThinking(steps: extraSteps)
            }

            var applyResult = PlanMutationApplier.ApplyResult()
            let hasMultiDayCommit = response.mutations.contains { $0.kind == .createMultiDayTask }
            if !response.mutations.isEmpty {
                var meds = medications
                applyResult = await applier.apply(
                    mutations: response.mutations,
                    tasksVM: tasksVM,
                    modulesVM: modulesVM,
                    userId: userId,
                    medications: &meds,
                    userMessage: message,
                    lifeProfile: context.lifeProfile
                )
                medications = meds
                await refreshContext()
                NotificationCenter.default.post(name: .taskListDidChange, object: nil)
                if hasMultiDayCommit {
                    multiDaySession = MultiDayPlanningSession(phase: .committed, draft: multiDayDraft)
                    multiDayDraft = nil
                    multiDayPlanning = nil
                }
            }

            recentDeltas = response.timelineDeltas
            negotiation = response.negotiation?.isActive == true ? response.negotiation : nil

            if let draft = response.multiDayDraft {
                multiDayDraft = draft
                multiDaySession = MultiDayPlanningSession(
                    phase: .preview,
                    draft: draft,
                    conversationContext: (multiDaySession?.conversationContext ?? []) + [message]
                )
            } else if !hasMultiDayCommit, response.multiDayPlanning == nil, multiDaySession?.phase != .preview {
                // Keep session in discovering unless we have a preview
            }

            multiDayPlanning = response.multiDayPlanning?.isActive == true ? response.multiDayPlanning : nil
            if multiDayPlanning == nil, multiDayDraft != nil, !hasMultiDayCommit {
                multiDayPlanning = PlanningNegotiation(
                    question: "Does this plan work for you?",
                    options: ["Schedule it", "Use fewer days", "Use more days", "Change the slices", "Cancel"]
                )
            }

            var displayReply = PlanningResponseParser.userFacingReply(response)
            displayReply = appendApplyNotices(to: displayReply, applyResult: applyResult)
            turns.append(PlanningConversationTurn(
                role: .assistant,
                text: displayReply,
                sourceUserMessage: message,
                responseSource: response.planningSource
            ))

            if inputMode == .voice {
                onSpeakReply?(displayReply)
            }

            if applyResult.appliedCount == 0, !response.mutations.isEmpty {
                print("[ExecutivePlanning] mutations skipped: \(applyResult.skippedReasons)")
            }
        } catch {
            errorMessage = error.localizedDescription
            let fallback = userFacingPlanningError(error)
            turns.append(PlanningConversationTurn(
                role: .assistant,
                text: fallback,
                sourceUserMessage: message,
                responseSource: .offline
            ))
            if inputMode == .voice {
                onSpeakReply?(fallback)
            }
        }

        isProcessing = false
        visibleThinkingStep = nil
    }

    public func selectNegotiationOption(
        _ option: String,
        context: PlanningConversationContext,
        tasksVM: TasksViewModel,
        modulesVM: LifeModulesViewModel,
        userId: String,
        refreshContext: @escaping () async -> Void
    ) async {
        if multiDayPlanning?.options.contains(option) == true {
            multiDayPlanning = nil
            if isMultiDayConfirmOption(option) {
                await commitMultiDayPlan(
                    context: context,
                    tasksVM: tasksVM,
                    modulesVM: modulesVM,
                    userId: userId,
                    refreshContext: refreshContext
                )
                return
            }
            if option.lowercased().contains("cancel") {
                multiDayDraft = nil
                multiDaySession = nil
                turns.append(PlanningConversationTurn(role: .assistant, text: "No problem — multi-day planning cancelled."))
                return
            }
        }
        negotiation = nil
        await submit(
            text: option,
            startedWithVoice: inputMode == .voice,
            context: context,
            tasksVM: tasksVM,
            modulesVM: modulesVM,
            userId: userId,
            refreshContext: refreshContext
        )
    }

    public func commitMultiDayPlan(
        context: PlanningConversationContext,
        tasksVM: TasksViewModel,
        modulesVM: LifeModulesViewModel,
        userId: String,
        refreshContext: @escaping () async -> Void
    ) async {
        guard let draft = multiDayDraft else { return }
        isProcessing = true
        defer { isProcessing = false }

        let mutation = PlanMutation(
            kind: .createMultiDayTask,
            title: draft.title,
            reason: draft.reasoning,
            dayCount: draft.dayCount,
            deadlineISO: draft.deadline.map { ISO8601DateFormatter().string(from: $0) },
            sliceDrafts: draft.slices
        )
        var meds = medications
        let applyResult = await applier.apply(
            mutations: [mutation],
            tasksVM: tasksVM,
            modulesVM: modulesVM,
            userId: userId,
            medications: &meds,
            lifeProfile: context.lifeProfile
        )
        medications = meds
        await refreshContext()
        NotificationCenter.default.post(name: .taskListDidChange, object: nil)

        multiDaySession = MultiDayPlanningSession(phase: .committed, draft: draft)
        multiDayDraft = nil
        multiDayPlanning = nil

        let todaySlice = draft.slices.sorted { $0.dayIndex < $1.dayIndex }.first
        let reply = "Done — \(draft.title) is spread across \(draft.dayCount) days. Today: \(todaySlice?.title ?? draft.title)."
        turns.append(PlanningConversationTurn(role: .assistant, text: appendApplyNotices(to: reply, applyResult: applyResult)))
        if inputMode == .voice {
            onSpeakReply?(reply)
        }
    }

    private func isMultiDayConfirmOption(_ option: String) -> Bool {
        let lower = option.lowercased()
        return lower.contains("schedule") || lower.contains("looks good")
    }

    /// Active multi-day goal banner data for Today view.
    public var activeMultiDayBanner: (title: String, dayIndex: Int, dayCount: Int, sliceTitle: String)? {
        guard let draft = multiDayDraft ?? multiDaySession?.draft else { return nil }
        let sorted = draft.slices.sorted { $0.dayIndex < $1.dayIndex }
        let todaySlice = sorted.first { $0.dayIndex == 0 } ?? sorted.first
        guard let slice = todaySlice else { return nil }
        return (draft.title, slice.dayIndex + 1, draft.dayCount, slice.title)
    }

    public func setInputMode(_ mode: PlanningInputMode) {
        inputMode = mode
    }

    // MARK: - Helpers

    private func animateThinking(steps: [String]) async {
        thinkingSteps = steps
        for step in steps {
            withAnimation(.easeInOut(duration: 0.25)) {
                visibleThinkingStep = step
            }
            try? await Task.sleep(nanoseconds: 450_000_000)
        }
    }

    private func mergeDeltas(into rows: [ExecutivePlanningTimelineRow]) -> [ExecutivePlanningTimelineRow] {
        guard !recentDeltas.isEmpty else { return rows }
        var merged = rows
        for delta in recentDeltas {
            if let idx = merged.firstIndex(where: { $0.title.localizedCaseInsensitiveContains(delta.title) || delta.title.localizedCaseInsensitiveContains($0.title) }) {
                merged[idx].change = delta.change
                merged[idx].isConflict = delta.isConflict
            } else if delta.change == .added || delta.change == .moved {
                merged.append(ExecutivePlanningTimelineRow(
                    id: delta.id,
                    sortDate: Self.sortDate(from: delta.timeLabel, reference: Date()),
                    timeLabel: delta.timeLabel,
                    title: delta.title,
                    subtitle: delta.subtitle ?? "",
                    kind: .work,
                    change: delta.change,
                    isConflict: delta.isConflict
                ))
            }
        }
        return merged.sorted { $0.sortDate < $1.sortDate }
    }

    private static func rows(from events: [LifeTimelineEvent], now: Date) -> [ExecutivePlanningTimelineRow] {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        let sorted = events.sorted { $0.date < $1.date }
        let currentIndex = currentEventIndex(in: sorted, now: now)

        return sorted.enumerated().map { index, event in
            row(from: event, index: index, currentIndex: currentIndex, now: now, formatter: formatter, isPreview: false)
        }
    }

    /// Tomorrow preview — everything is upcoming; no "now" or "past" markers.
    static func previewRows(from events: [LifeTimelineEvent]) -> [ExecutivePlanningTimelineRow] {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let sorted = events.sorted { $0.date < $1.date }
        return sorted.enumerated().map { index, event in
            row(from: event, index: index, currentIndex: nil, now: Date(), formatter: formatter, isPreview: true)
        }
    }

    private static func row(
        from event: LifeTimelineEvent,
        index: Int,
        currentIndex: Int?,
        now: Date,
        formatter: DateFormatter,
        isPreview: Bool
    ) -> ExecutivePlanningTimelineRow {
        let end = eventEndDate(event)
        let endLabel = formatter.string(from: end)
        let rangeLabel = ScheduleTimeFormatting.rangeLabel(from: event.date, to: end)
        let isPast = !isPreview && !event.isCompleted && end < now
        let isCompleted = event.isCompleted
        let isNow = !isPreview && !isCompleted && !isPast && currentIndex == index

        return ExecutivePlanningTimelineRow(
            id: event.id,
            sortDate: event.date,
            timeLabel: formatter.string(from: event.date),
            endTimeLabel: endLabel,
            scheduleRangeLabel: rangeLabel,
            title: event.title,
            subtitle: previewSubtitle(for: event, isPast: isPast, isCompleted: isCompleted, isPreview: isPreview),
            detailLines: event.detailLines,
            kind: event.kind,
            isNow: isNow,
            isCompleted: isCompleted,
            isPast: isPast,
            taskId: Self.taskId(from: event.id),
            estimatedMinutes: event.estimatedMinutes,
            completedAt: event.completedAt,
            isFixedEvent: event.isFixed
        )
    }

    private static func previewSubtitle(
        for event: LifeTimelineEvent,
        isPast: Bool,
        isCompleted: Bool,
        isPreview: Bool
    ) -> String {
        if isPreview {
            if event.isFixed { return "Fixed commitment" }
            return event.subtitle.isEmpty ? "Planned" : event.subtitle
        }
        return subtitle(for: event, isPast: isPast, isCompleted: isCompleted)
    }

    private static func subtitle(for event: LifeTimelineEvent, isPast: Bool, isCompleted: Bool) -> String {
        if isCompleted { return "Done" }
        if isPast { return "Scheduled earlier today" }
        return event.subtitle
    }

    private static func taskId(from eventId: String) -> String? {
        guard eventId.hasPrefix("task-") else { return nil }
        let id = String(eventId.dropFirst(5))
        return id.isEmpty ? nil : id
    }

    /// Event in progress, or the next upcoming one — drives the glowing timeline dot.
    private static func currentEventIndex(in events: [LifeTimelineEvent], now: Date) -> Int? {
        for (index, event) in events.enumerated() {
            guard !event.isCompleted else { continue }
            let end = eventEndDate(event)
            if event.date <= now, now <= end { return index }
        }
        return events.firstIndex { !$0.isCompleted && $0.date > now }
    }

    private static func eventEndDate(_ event: LifeTimelineEvent) -> Date {
        let minutes = event.estimatedMinutes ?? 30
        return event.date.addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// Parses "h:mm a" labels from planner deltas into today's timeline order.
    private static func sortDate(from timeLabel: String, reference: Date) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        guard let parsed = formatter.date(from: timeLabel) else { return reference }
        let calendar = Calendar.current
        var components = calendar.dateComponents([.hour, .minute], from: parsed)
        components.year = calendar.component(.year, from: reference)
        components.month = calendar.component(.month, from: reference)
        components.day = calendar.component(.day, from: reference)
        return calendar.date(from: components) ?? reference
    }

    public static func buildContext(
        userName: String,
        tasksVM: TasksViewModel,
        timelineItems: [LifeTimelineEvent],
        snapshot: LifeContextSnapshot?,
        healthSummary: HealthSummary?,
        executiveCapacity: ExecutiveCapacityState? = nil,
        analyticsContext: CachedAIContextSummary? = nil
    ) -> PlanningConversationContext {
        let medications = MedicationStore.load()
        let capacity = executiveCapacity ?? .moderate
        let energy = legacyEnergyPercent(for: capacity.band)
        let profileRemaining = UserLifeProfileStore.remainingWorkMinutes()
        let available = snapshot?.availableTimeMinutes ?? min(profileRemaining, 480)

        let nextMeeting = timelineItems
            .filter { $0.kind == .meeting && $0.date > Date() }
            .sorted { $0.date < $1.date }
            .first

        let meetingMinutes: Int?
        if let nextMeeting {
            meetingMinutes = max(0, Int(nextMeeting.date.timeIntervalSinceNow / 60))
        } else {
            meetingMinutes = nil
        }

        var planParts: [String] = []
        if let sleep = healthSummary?.totalSleepMinutes {
            planParts.append("Sleep \(String(format: "%.1f", sleep / 60))h")
        }
        planParts.append("\(tasksVM.tasks.filter { $0.status.isActive }.count) active tasks")

        return PlanningConversationContext(
            userName: userName,
            tasks: tasksVM.tasks,
            timelineItems: timelineItems,
            medications: medications,
            availableMinutes: available,
            energyPercent: energy,
            executiveCapacityLabel: capacity.band.displayLabel,
            executiveCapacityReasons: capacity.reasoning.reasons,
            nextMeetingTitle: nextMeeting?.title,
            nextMeetingMinutes: meetingMinutes,
            planSummary: planParts.joined(separator: " · "),
            completedTodayCount: tasksVM.completedToday.count,
            lifeProfile: UserLifeProfileStore.load(),
            analyticsContext: analyticsContext,
            healthSummary: healthSummary
        )
    }

    private static func legacyEnergyPercent(for band: ExecutiveCapacityBand) -> Int {
        switch band {
        case .peakFocus: return 90
        case .goodCapacity: return 72
        case .moderateCapacity: return 55
        case .lowCapacity: return 38
        case .recoveryMode: return 22
        }
    }

    private func userFacingPlanningError(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return "I hit a snag updating your plan. Try again in a moment."
    }
}
