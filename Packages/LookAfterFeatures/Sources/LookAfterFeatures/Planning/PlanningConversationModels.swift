import Foundation
import LookAfterCore

// MARK: - Input modality

public enum PlanningInputMode: String, Codable, Sendable, Equatable {
    case text
    case voice
}

// MARK: - Conversation turn

public enum PlanningTurnRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

/// How the assistant produced a planning response.
public enum PlanningResponseSource: String, Codable, Sendable, Equatable {
    case ai
    case offline
}

public struct PlanningConversationTurn: Identifiable, Sendable, Equatable {
    public let id: String
    public let role: PlanningTurnRole
    public var text: String
    public let createdAt: Date
    /// User message this assistant reply was based on — used for AI redesign.
    public var sourceUserMessage: String?
    public var responseSource: PlanningResponseSource?

    public init(
        id: String = UUID().uuidString,
        role: PlanningTurnRole,
        text: String,
        createdAt: Date = Date(),
        sourceUserMessage: String? = nil,
        responseSource: PlanningResponseSource? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.sourceUserMessage = sourceUserMessage
        self.responseSource = responseSource
    }

    public var offersAIRedesign: Bool {
        role == .assistant
            && responseSource == .offline
            && sourceUserMessage?.isEmpty == false
    }
}

// MARK: - LLM structured response

public struct PlanVariant: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var label: String
    public var summary: String
    public var tradeoffs: [String]
    public var scheduleChanges: [DayReplanScheduleChange]
    public var timelineDeltas: [PlanningTimelineDelta]
    public var recommended: Bool

    public init(
        id: String = UUID().uuidString,
        label: String,
        summary: String,
        tradeoffs: [String] = [],
        scheduleChanges: [DayReplanScheduleChange] = [],
        timelineDeltas: [PlanningTimelineDelta] = [],
        recommended: Bool = false
    ) {
        self.id = id
        self.label = label
        self.summary = summary
        self.tradeoffs = tradeoffs
        self.scheduleChanges = scheduleChanges
        self.timelineDeltas = timelineDeltas
        self.recommended = recommended
    }
}

public enum PlanningNegotiationPhase: String, Sendable, Equatable {
    case idle
    case proposingVariants
    case awaitingSelection
}

public struct PlanningTurnResponse: Sendable, Equatable {
    public var reply: String
    public var thinkingSteps: [String]
    public var mutations: [PlanMutation]
    public var negotiation: PlanningNegotiation?
    public var planVariants: [PlanVariant]?
    public var multiDayDraft: MultiDayPlanDraft?
    public var multiDayPlanning: PlanningNegotiation?
    public var timelineDeltas: [PlanningTimelineDelta]
    /// Set by the engine after parsing — not part of LLM JSON.
    public var planningSource: PlanningResponseSource

    public init(
        reply: String,
        thinkingSteps: [String] = [],
        mutations: [PlanMutation] = [],
        negotiation: PlanningNegotiation? = nil,
        planVariants: [PlanVariant]? = nil,
        multiDayDraft: MultiDayPlanDraft? = nil,
        multiDayPlanning: PlanningNegotiation? = nil,
        timelineDeltas: [PlanningTimelineDelta] = [],
        planningSource: PlanningResponseSource = .ai
    ) {
        self.reply = reply
        self.thinkingSteps = thinkingSteps
        self.mutations = mutations
        self.negotiation = negotiation
        self.planVariants = planVariants
        self.multiDayDraft = multiDayDraft
        self.multiDayPlanning = multiDayPlanning
        self.timelineDeltas = timelineDeltas
        self.planningSource = planningSource
    }
}

extension PlanningTurnResponse: Codable {
    enum CodingKeys: String, CodingKey {
        case reply, thinkingSteps, mutations, negotiation, planVariants, multiDayDraft, multiDayPlanning, timelineDeltas
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reply = try container.decode(String.self, forKey: .reply)
        thinkingSteps = try container.decodeIfPresent([String].self, forKey: .thinkingSteps) ?? []
        mutations = try container.decodeIfPresent([PlanMutation].self, forKey: .mutations) ?? []
        negotiation = try container.decodeIfPresent(PlanningNegotiation.self, forKey: .negotiation)
        planVariants = try container.decodeIfPresent([PlanVariant].self, forKey: .planVariants)
        multiDayDraft = try container.decodeIfPresent(MultiDayPlanDraft.self, forKey: .multiDayDraft)
        multiDayPlanning = try container.decodeIfPresent(PlanningNegotiation.self, forKey: .multiDayPlanning)
        timelineDeltas = try container.decodeIfPresent([PlanningTimelineDelta].self, forKey: .timelineDeltas) ?? []
        planningSource = .ai
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reply, forKey: .reply)
        try container.encode(thinkingSteps, forKey: .thinkingSteps)
        try container.encode(mutations, forKey: .mutations)
        try container.encodeIfPresent(negotiation, forKey: .negotiation)
        try container.encodeIfPresent(planVariants, forKey: .planVariants)
        try container.encodeIfPresent(multiDayDraft, forKey: .multiDayDraft)
        try container.encodeIfPresent(multiDayPlanning, forKey: .multiDayPlanning)
        try container.encode(timelineDeltas, forKey: .timelineDeltas)
    }
}

public struct PlanningNegotiation: Codable, Sendable, Equatable {
    public var question: String
    public var options: [String]
    /// Maps option label at same index to a pre-built plan variant id.
    public var optionVariantIDs: [String]?

    public init(question: String, options: [String], optionVariantIDs: [String]? = nil) {
        self.question = question
        self.options = options
        self.optionVariantIDs = optionVariantIDs
    }

    public var isActive: Bool {
        !question.isEmpty && !options.isEmpty
    }

    public func variantID(forOption option: String) -> String? {
        guard let ids = optionVariantIDs, ids.count == options.count,
              let index = options.firstIndex(of: option) else { return nil }
        return ids[index]
    }
}

/// Pending AI schedule changes awaiting explicit user approval (P1).
public struct PendingPlanApproval: Identifiable, Sendable, Equatable {
    public var id: String
    public var reason: String
    public var changeSummaries: [String]
    public var mutations: [PlanMutation]
    public var userMessage: String?
    public var touchesUserPlaced: Bool

    public init(
        id: String = UUID().uuidString,
        reason: String,
        changeSummaries: [String],
        mutations: [PlanMutation],
        userMessage: String? = nil,
        touchesUserPlaced: Bool = false
    ) {
        self.id = id
        self.reason = reason
        self.changeSummaries = changeSummaries
        self.mutations = mutations
        self.userMessage = userMessage
        self.touchesUserPlaced = touchesUserPlaced
    }

    public static func make(
        mutations: [PlanMutation],
        reply: String,
        userMessage: String?,
        tasks: [LifeTask]
    ) -> PendingPlanApproval {
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var touchesUserPlaced = false
        let summaries: [String] = mutations.map { mutation in
            if let id = mutation.taskID, let task = byID[id], task.userPlacedScheduleAt != nil {
                touchesUserPlaced = true
            }
            return mutation.approvalSummary(taskLookup: byID)
        }
        let reason = mutations.compactMap(\.reason).first(where: { !$0.isEmpty })
            ?? (reply.isEmpty ? "Suggested schedule updates" : String(reply.prefix(180)))
        return PendingPlanApproval(
            reason: reason,
            changeSummaries: summaries,
            mutations: mutations,
            userMessage: userMessage,
            touchesUserPlaced: touchesUserPlaced
        )
    }
}

extension PlanMutation {
    /// One-line change description for the approval card.
    public func approvalSummary(taskLookup: [String: LifeTask]) -> String {
        let title = self.title
            ?? taskID.flatMap { taskLookup[$0]?.title }
            ?? "Task"
        switch kind {
        case .createTask:
            if let h = startHour, let m = startMinute {
                return "Create \"\(title)\" at \(String(format: "%d:%02d", h, m))"
            }
            return "Create \"\(title)\""
        case .rescheduleTask:
            if deferToTomorrow { return "Move \"\(title)\" to tomorrow" }
            if let h = startHour, let m = startMinute {
                return "Reschedule \"\(title)\" to \(String(format: "%d:%02d", h, m))"
            }
            return "Reschedule \"\(title)\""
        case .deferTask:
            return "Defer \"\(title)\""
        case .completeTask:
            return "Complete \"\(title)\""
        case .createMultiDayTask:
            return "Schedule multi-day \"\(title)\""
        case .reuseTask:
            return "Reuse existing \"\(title)\""
        case .markMedicationTaken:
            return "Mark medication taken"
        case .addShoppingItem:
            return "Add shopping: \(shoppingItemName ?? title)"
        case .captureNote:
            return "Add note"
        case .removeFromToday:
            return "Remove \"\(title)\" from today"
        }
    }
}

// MARK: - Multi-day planning

public enum MultiDayPlanningPhase: String, Codable, Sendable {
    case discovering
    case preview
    case committed
}

public struct MultiDaySliceDraft: Sendable, Equatable, Codable, Identifiable {
    public var id: String { "\(dayIndex)-\(title)" }
    public var dayIndex: Int
    public var title: String
    public var estimatedMinutes: Int
    public var windowLabel: String?

    public init(dayIndex: Int, title: String, estimatedMinutes: Int, windowLabel: String? = nil) {
        self.dayIndex = dayIndex
        self.title = title
        self.estimatedMinutes = estimatedMinutes
        self.windowLabel = windowLabel
    }
}

public struct MultiDayPlanDraft: Sendable, Equatable, Identifiable, Codable {
    public var id: String
    public var title: String
    public var dayCount: Int
    public var lifeArea: LifeArea
    public var deadline: Date?
    public var slices: [MultiDaySliceDraft]
    public var reasoning: String

    public init(
        id: String = UUID().uuidString,
        title: String,
        dayCount: Int,
        lifeArea: LifeArea = .work,
        deadline: Date? = nil,
        slices: [MultiDaySliceDraft] = [],
        reasoning: String = ""
    ) {
        self.id = id
        self.title = title
        self.dayCount = dayCount
        self.lifeArea = lifeArea
        self.deadline = deadline
        self.slices = slices
        self.reasoning = reasoning
    }
}

public struct MultiDayPlanningSession: Sendable, Equatable {
    public var phase: MultiDayPlanningPhase
    public var draft: MultiDayPlanDraft?
    public var conversationContext: [String]

    public init(
        phase: MultiDayPlanningPhase = .discovering,
        draft: MultiDayPlanDraft? = nil,
        conversationContext: [String] = []
    ) {
        self.phase = phase
        self.draft = draft
        self.conversationContext = conversationContext
    }
}

public struct PlanningTimelineDelta: Identifiable, Sendable, Equatable {
    public var id: String
    public var timeLabel: String
    public var title: String
    public var subtitle: String?
    public var change: PlanningTimelineChange
    public var isConflict: Bool

    public init(
        id: String = UUID().uuidString,
        timeLabel: String,
        title: String,
        subtitle: String? = nil,
        change: PlanningTimelineChange,
        isConflict: Bool = false
    ) {
        self.id = id
        self.timeLabel = timeLabel
        self.title = title
        self.subtitle = subtitle
        self.change = change
        self.isConflict = isConflict
    }
}

extension PlanningTimelineDelta: Codable {
    enum CodingKeys: String, CodingKey {
        case id, timeLabel, title, subtitle, change, isConflict
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        timeLabel = try container.decodeIfPresent(String.self, forKey: .timeLabel) ?? "—"
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        if let changeRaw = try container.decodeIfPresent(String.self, forKey: .change) {
            change = PlanningTimelineChange.fromLLM(changeRaw) ?? .added
        } else {
            change = .added
        }
        isConflict = try container.decodeIfPresent(Bool.self, forKey: .isConflict) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timeLabel, forKey: .timeLabel)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        try container.encode(change.rawValue, forKey: .change)
        try container.encode(isConflict, forKey: .isConflict)
    }
}

public enum PlanningTimelineChange: String, Codable, Sendable {
    case added
    case moved
    case removed
    case reused
    case unchanged
    case conflict
}

// MARK: - Plan mutations

public struct PlanMutation: Sendable, Equatable, Identifiable {
    public var id: String
    public var kind: PlanMutationKind
    public var taskID: String?
    public var title: String?
    public var estimatedMinutes: Int?
    public var priority: Priority?
    public var startHour: Int?
    public var startMinute: Int?
    public var deferToTomorrow: Bool
    public var medicationID: String?
    public var shoppingItemName: String?
    public var captureNote: String?
    public var reason: String?
    public var dayCount: Int?
    public var deadlineISO: String?
    public var sliceDrafts: [MultiDaySliceDraft]?

    public init(
        id: String = UUID().uuidString,
        kind: PlanMutationKind,
        taskID: String? = nil,
        title: String? = nil,
        estimatedMinutes: Int? = nil,
        priority: Priority? = nil,
        startHour: Int? = nil,
        startMinute: Int? = nil,
        deferToTomorrow: Bool = false,
        medicationID: String? = nil,
        shoppingItemName: String? = nil,
        captureNote: String? = nil,
        reason: String? = nil,
        dayCount: Int? = nil,
        deadlineISO: String? = nil,
        sliceDrafts: [MultiDaySliceDraft]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.taskID = taskID
        self.title = title
        self.estimatedMinutes = estimatedMinutes
        self.priority = priority
        self.startHour = startHour
        self.startMinute = startMinute
        self.deferToTomorrow = deferToTomorrow
        self.medicationID = medicationID
        self.shoppingItemName = shoppingItemName
        self.captureNote = captureNote
        self.reason = reason
        self.dayCount = dayCount
        self.deadlineISO = deadlineISO
        self.sliceDrafts = sliceDrafts
    }
}

extension PlanMutation: Codable {
    enum CodingKeys: String, CodingKey {
        case id, kind, type, action, taskID, taskId, task_id, title
        case estimatedMinutes, estimated_minutes, priority, startHour, start_hour
        case startMinute, start_minute, deferToTomorrow, medicationID, medicationId
        case shoppingItemName, shopping_item_name, captureNote, reason
        case dayCount, day_count, deadlineISO, deadline_iso, slices, sliceDrafts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString

        let kindRaw = (try? container.decodeIfPresent(String.self, forKey: .kind))
            ?? (try? container.decodeIfPresent(String.self, forKey: .type))
            ?? (try? container.decodeIfPresent(String.self, forKey: .action))
            ?? nil
        guard let kindRaw, let parsedKind = PlanMutationKind.fromLLM(kindRaw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown mutation kind"))
        }
        kind = parsedKind

        taskID = (try? container.decodeIfPresent(String.self, forKey: .taskID))
            ?? (try? container.decodeIfPresent(String.self, forKey: .taskId))
            ?? (try? container.decodeIfPresent(String.self, forKey: .task_id))
            ?? nil
        title = try container.decodeIfPresent(String.self, forKey: .title)
        estimatedMinutes = (try? container.decodeIfPresent(Int.self, forKey: .estimatedMinutes))
            ?? (try? container.decodeIfPresent(Int.self, forKey: .estimated_minutes))
            ?? nil
        if let priorityLabel = try? container.decodeIfPresent(String.self, forKey: .priority) {
            priority = Priority.fromLLM(priorityLabel)
        } else {
            priority = nil
        }
        startHour = (try? container.decodeIfPresent(Int.self, forKey: .startHour))
            ?? (try? container.decodeIfPresent(Int.self, forKey: .start_hour))
            ?? nil
        startMinute = (try? container.decodeIfPresent(Int.self, forKey: .startMinute))
            ?? (try? container.decodeIfPresent(Int.self, forKey: .start_minute))
            ?? nil
        deferToTomorrow = (try? container.decodeIfPresent(Bool.self, forKey: .deferToTomorrow)) ?? false
        medicationID = (try? container.decodeIfPresent(String.self, forKey: .medicationID))
            ?? (try? container.decodeIfPresent(String.self, forKey: .medicationId))
            ?? nil
        shoppingItemName = (try? container.decodeIfPresent(String.self, forKey: .shoppingItemName))
            ?? (try? container.decodeIfPresent(String.self, forKey: .shopping_item_name))
            ?? nil
        captureNote = try? container.decodeIfPresent(String.self, forKey: .captureNote)
        reason = try? container.decodeIfPresent(String.self, forKey: .reason)
        dayCount = (try? container.decodeIfPresent(Int.self, forKey: .dayCount))
            ?? (try? container.decodeIfPresent(Int.self, forKey: .day_count))
            ?? nil
        deadlineISO = (try? container.decodeIfPresent(String.self, forKey: .deadlineISO))
            ?? (try? container.decodeIfPresent(String.self, forKey: .deadline_iso))
            ?? nil
        if let decodedSlices = try? container.decodeIfPresent([MultiDaySliceDraft].self, forKey: .slices) {
            sliceDrafts = decodedSlices
        } else {
            sliceDrafts = try? container.decodeIfPresent([MultiDaySliceDraft].self, forKey: .sliceDrafts)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind.rawValue, forKey: .kind)
        try container.encodeIfPresent(taskID, forKey: .taskID)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(estimatedMinutes, forKey: .estimatedMinutes)
        try container.encodeIfPresent(priority?.label, forKey: .priority)
        try container.encodeIfPresent(startHour, forKey: .startHour)
        try container.encodeIfPresent(startMinute, forKey: .startMinute)
        try container.encode(deferToTomorrow, forKey: .deferToTomorrow)
        try container.encodeIfPresent(medicationID, forKey: .medicationID)
        try container.encodeIfPresent(shoppingItemName, forKey: .shoppingItemName)
        try container.encodeIfPresent(captureNote, forKey: .captureNote)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encodeIfPresent(dayCount, forKey: .dayCount)
        try container.encodeIfPresent(deadlineISO, forKey: .deadlineISO)
        try container.encodeIfPresent(sliceDrafts, forKey: .slices)
    }
}

public enum PlanMutationKind: String, Codable, Sendable, CaseIterable {
    case reuseTask
    case createTask
    case rescheduleTask
    case deferTask
    case completeTask
    case markMedicationTaken
    case addShoppingItem
    case captureNote
    case removeFromToday
    case createMultiDayTask
}

// MARK: - Live timeline row (UI)

public struct ExecutivePlanningTimelineRow: Identifiable, Sendable, Equatable {
    public let id: String
    public var sortDate: Date
    public var timeLabel: String
    public var endTimeLabel: String
    public var scheduleRangeLabel: String
    public var title: String
    public var subtitle: String
    public var detailLines: [String]
    public var kind: LifeTimelineEventKind
    public var emoji: String
    public var icon: String
    public var isNow: Bool
    public var change: PlanningTimelineChange
    public var isConflict: Bool
    public var isCompleted: Bool
    /// Scheduled window ended but user has not checked the task off.
    public var isPast: Bool
    /// NOW row whose window already ended.
    public var isLate: Bool
    /// Underlying LifeTask id when this row represents a completable task.
    public var taskId: String?
    public var estimatedMinutes: Int?
    public var completedAt: Date?
    public var isFixedEvent: Bool
    /// Semantic time lock for interactive physics (defaults flexible).
    public var timeConstraint: TimeConstraint
    public var scheduleKind: TimelineScheduleKind = .fixedWindow
    /// Display-only slot from planner when task could not be persisted (overcommitted day).
    public var isSuggestedSlot: Bool = false
    public var suggestedStart: Date?
    /// Real task id for a suggested slot row (`taskId` stays nil until Add to day).
    public var suggestedSourceTaskId: String?
    /// Flexible task with no user-set clock slot — sort may use a gap-anchor; never paint it as wall clock.
    public var isUnslottedFlexible: Bool = false

    public var canReschedule: Bool {
        guard taskId != nil, !isCompleted, !isSuggestedSlot else { return false }
        if isFixedEvent || timeConstraint == .anchored, !isPast { return false }
        return timeConstraint.isSchedulerMovable
    }

    public var canRemoveFromTimeline: Bool {
        guard taskId != nil, !isCompleted, !isSuggestedSlot else { return false }
        if isFixedEvent || timeConstraint == .anchored { return false }
        return timeConstraint.isSchedulerMovable
    }

    public init(
        id: String,
        sortDate: Date = Date(),
        timeLabel: String,
        endTimeLabel: String = "",
        scheduleRangeLabel: String = "",
        title: String,
        subtitle: String = "",
        detailLines: [String] = [],
        kind: LifeTimelineEventKind = .work,
        emoji: String? = nil,
        icon: String? = nil,
        isNow: Bool = false,
        change: PlanningTimelineChange = .unchanged,
        isConflict: Bool = false,
        isCompleted: Bool = false,
        isPast: Bool = false,
        isLate: Bool = false,
        taskId: String? = nil,
        estimatedMinutes: Int? = nil,
        completedAt: Date? = nil,
        isFixedEvent: Bool = false,
        timeConstraint: TimeConstraint = .flexible,
        scheduleKind: TimelineScheduleKind = .fixedWindow,
        isSuggestedSlot: Bool = false,
        suggestedStart: Date? = nil,
        suggestedSourceTaskId: String? = nil,
        isUnslottedFlexible: Bool = false
    ) {
        self.id = id
        self.sortDate = sortDate
        self.timeLabel = timeLabel
        self.endTimeLabel = endTimeLabel
        self.scheduleRangeLabel = scheduleRangeLabel.isEmpty && !endTimeLabel.isEmpty
            ? "\(timeLabel) to \(endTimeLabel)"
            : scheduleRangeLabel
        self.title = title
        self.subtitle = subtitle
        self.detailLines = detailLines
        self.kind = kind
        self.emoji = emoji ?? kind.emoji
        self.icon = icon ?? kind.icon
        self.isNow = isNow
        self.change = change
        self.isConflict = isConflict
        self.isCompleted = isCompleted
        self.isPast = isPast
        self.isLate = isLate
        self.taskId = taskId
        self.estimatedMinutes = estimatedMinutes
        self.completedAt = completedAt
        self.isFixedEvent = isFixedEvent
        self.timeConstraint = isFixedEvent && timeConstraint == .flexible ? .anchored : timeConstraint
        self.scheduleKind = scheduleKind
        self.isSuggestedSlot = isSuggestedSlot
        self.suggestedStart = suggestedStart
        self.suggestedSourceTaskId = suggestedSourceTaskId
        self.isUnslottedFlexible = isUnslottedFlexible
    }
}

public struct PlanningConversationContext: Sendable {
    public var userName: String
    public var tasks: [LifeTask]
    public var timelineItems: [LifeTimelineEvent]
    public var medications: [Medication]
    public var availableMinutes: Int
    /// Legacy numeric hint — prefer `executiveCapacityLabel` in prompts.
    public var energyPercent: Int
    public var executiveCapacityLabel: String
    public var executiveCapacityReasons: [String]
    public var nextMeetingTitle: String?
    public var nextMeetingMinutes: Int?
    public var planSummary: String
    public var completedTodayCount: Int
    public var lifeProfile: UserLifeProfile
    public var analyticsContext: CachedAIContextSummary?
    public var healthSummary: HealthSummary?

    public init(
        userName: String,
        tasks: [LifeTask],
        timelineItems: [LifeTimelineEvent],
        medications: [Medication],
        availableMinutes: Int,
        energyPercent: Int,
        executiveCapacityLabel: String = "Moderate Capacity",
        executiveCapacityReasons: [String] = [],
        nextMeetingTitle: String? = nil,
        nextMeetingMinutes: Int? = nil,
        planSummary: String = "",
        completedTodayCount: Int = 0,
        lifeProfile: UserLifeProfile = UserLifeProfile(),
        analyticsContext: CachedAIContextSummary? = nil,
        healthSummary: HealthSummary? = nil
    ) {
        self.userName = userName
        self.tasks = tasks
        self.timelineItems = timelineItems
        self.medications = medications
        self.availableMinutes = availableMinutes
        self.energyPercent = energyPercent
        self.executiveCapacityLabel = executiveCapacityLabel
        self.executiveCapacityReasons = executiveCapacityReasons
        self.nextMeetingTitle = nextMeetingTitle
        self.nextMeetingMinutes = nextMeetingMinutes
        self.planSummary = planSummary
        self.completedTodayCount = completedTodayCount
        self.lifeProfile = lifeProfile
        self.analyticsContext = analyticsContext
        self.healthSummary = healthSummary
    }
}
