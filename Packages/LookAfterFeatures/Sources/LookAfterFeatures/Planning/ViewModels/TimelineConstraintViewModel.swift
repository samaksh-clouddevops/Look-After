import Foundation
import SwiftUI
import LookAfterCore

// MARK: - Intent

/// All user interactions for semantic time constraints route through intents.
public enum TimelineConstraintIntent: Equatable, Sendable {
    case hardenConstraint(taskID: String)
    case softenConstraint(taskID: String)
    case setConstraint(taskID: String, TimeConstraint)
    case beginVerticalDrag(taskID: String)
    case endVerticalDrag
    case updateVerticalDragPreview(taskID: String, proposedStart: Date?, anchorY: CGFloat?)
    case commitVerticalOffset(taskID: String, offsetMinutes: Int)
    case commitVerticalDrag(taskID: String, proposedStart: Date)
}

// MARK: - View model

/// Intent-driven mutation of timeline time constraints. Views must not apply business rules.
@MainActor
public final class TimelineConstraintViewModel: ObservableObject {
    @Published public private(set) var constraintsByTaskID: [String: TimeConstraint] = [:]
    @Published public private(set) var activeDragTaskID: String?
    @Published public private(set) var proposedDragStart: Date?
    @Published public private(set) var proposedDragDurationMinutes: Int?
    @Published public private(set) var dragAnchorY: CGFloat?
    @Published public private(set) var lastMutation: (taskID: String, constraint: TimeConstraint)?

    private var tasksByID: [String: LifeTask] = [:]
    private let telemetry: any InteractionTelemetryServing
    public var onTaskUpdated: ((LifeTask) -> Void)?
    /// Fired when a vertical drag successfully commits a new schedule time.
    public var onScheduleDragCommitted: (() -> Void)?
    /// EventKit peers for OccupiedDay (injected from shell / calendar sync).
    public var calendarEventsProvider: ((Date) -> [BriefingCalendarEvent])?
    public var lifeModelProvider: (() -> LifeModel?) = { LifeModelStore.load() }

    public init(
        telemetry: any InteractionTelemetryServing = InteractionTelemetryService.shared,
        onTaskUpdated: ((LifeTask) -> Void)? = nil
    ) {
        self.telemetry = telemetry
        self.onTaskUpdated = onTaskUpdated
    }

    // MARK: - Seed

    public func seed(tasks: [LifeTask]) {
        var map: [String: LifeTask] = [:]
        var constraints: [String: TimeConstraint] = [:]
        for task in tasks {
            map[task.id] = task
            constraints[task.id] = task.timeConstraintValue
        }
        tasksByID = map
        constraintsByTaskID = constraints
    }

    public func upsert(task: LifeTask) {
        tasksByID[task.id] = task
        constraintsByTaskID[task.id] = task.timeConstraintValue
    }

    public func constraint(for taskID: String) -> TimeConstraint {
        constraintsByTaskID[taskID]
            ?? tasksByID[taskID]?.timeConstraintValue
            ?? .flexible
    }

    // MARK: - Intent router

    public func handle(_ intent: TimelineConstraintIntent) {
        switch intent {
        case .hardenConstraint(let taskID):
            mutate(taskID: taskID, source: .swipe) { $0.hardened() }
        case .softenConstraint(let taskID):
            mutate(taskID: taskID, source: .swipe) { $0.softened() }
        case .setConstraint(let taskID, let value):
            mutate(taskID: taskID, source: .accessibility) { _ in value }
        case .beginVerticalDrag(let taskID):
            activeDragTaskID = taskID
            if let task = tasksByID[taskID] {
                proposedDragDurationMinutes = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
            } else {
                proposedDragDurationMinutes = TaskDurationPolicy.minimumMinutes
            }
        case .endVerticalDrag:
            activeDragTaskID = nil
            proposedDragStart = nil
            proposedDragDurationMinutes = nil
            dragAnchorY = nil
        case .updateVerticalDragPreview(_, let proposedStart, let anchorY):
            proposedDragStart = proposedStart
            dragAnchorY = anchorY
        case .commitVerticalOffset(let taskID, let offsetMinutes):
            commitScheduleOffset(taskID: taskID, minutes: offsetMinutes)
        case .commitVerticalDrag(let taskID, let proposedStart):
            commitAbsoluteStart(taskID: taskID, proposedStart: proposedStart)
        }
    }

    // MARK: - Private

    private func mutate(
        taskID: String,
        source: ConstraintChangeSource,
        transform: (TimeConstraint) -> TimeConstraint
    ) {
        let current = constraint(for: taskID)
        let next = transform(current)
        guard next != current else { return }

        constraintsByTaskID[taskID] = next
        lastMutation = (taskID, next)

        var title = ""
        var semanticType: String?
        if var task = tasksByID[taskID] {
            task.applyTimeConstraint(next)
            tasksByID[taskID] = task
            title = task.title
            semanticType = task.semanticProfile?.semanticType.rawValue
            onTaskUpdated?(task)
        }

        telemetry.recordConstraintChange(
            taskID: taskID,
            taskTitle: title,
            semanticType: semanticType,
            from: current,
            to: next,
            source: source
        )
    }

    private func commitAbsoluteStart(taskID: String, proposedStart: Date) {
        guard var task = tasksByID[taskID],
              task.timeConstraintValue != .anchored else {
            return
        }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: task.scheduledDate ?? proposedStart)
        let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
        let neighbors = Array(tasksByID.values).filter { $0.id != taskID && $0.status.isActive }
        let occupied = OccupiedDay.build(
            tasks: neighbors,
            calendarEvents: calendarEventsProvider?(day) ?? [],
            model: lifeModelProvider(),
            on: day,
            calendar: calendar,
            excludingTaskID: taskID
        ).occupiedForPlacement(excludingTaskID: taskID)
        let placement = SchedulePlacementGuard.evaluate(
            proposedStart: proposedStart,
            durationMinutes: duration,
            task: task,
            occupied: occupied,
            calendar: calendar,
            mode: .rejectOutsideBox,
            neighborTasks: neighbors
        )
        let start: Date
        switch placement {
        case .accepted(let date), .snapped(let date):
            start = date
        case .needsAI, .rejected:
            return
        }
        guard task.scheduledTime == nil || abs(task.scheduledTime!.timeIntervalSince(start)) > 30 else {
            return
        }

        task.scheduledTime = start
        task.scheduledEndTime = start.addingTimeInterval(TimeInterval(duration * 60))
        task.scheduledDate = day
        if TaskReaper.allowsStart(start, for: task, calendar: calendar) {
            TaskConstraintAlignment.markUserPlaced(&task)
        }
        task.updatedAt = Date()
        tasksByID[taskID] = task
        onTaskUpdated?(task)
        onScheduleDragCommitted?()
    }

    private func commitScheduleOffset(taskID: String, minutes: Int) {
        guard minutes != 0,
              var task = tasksByID[taskID],
              task.timeConstraintValue != .anchored else {
            return
        }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: task.scheduledDate ?? task.scheduledTime ?? Date())
        let duration = max(task.estimatedMinutes, TaskDurationPolicy.minimumMinutes)
        let base = task.scheduledTime ?? calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? Date()
        let proposed = base.addingTimeInterval(TimeInterval(minutes * 60))
        let neighbors = Array(tasksByID.values).filter { $0.id != taskID && $0.status.isActive }
        let occupied = OccupiedDay.build(
            tasks: neighbors,
            calendarEvents: calendarEventsProvider?(day) ?? [],
            model: lifeModelProvider(),
            on: day,
            calendar: calendar,
            excludingTaskID: taskID
        ).occupiedForPlacement(excludingTaskID: taskID)
        let placement = SchedulePlacementGuard.evaluate(
            proposedStart: proposed,
            durationMinutes: duration,
            task: task,
            occupied: occupied,
            calendar: calendar,
            mode: .rejectOutsideBox,
            neighborTasks: neighbors
        )
        let start: Date
        switch placement {
        case .accepted(let date), .snapped(let date):
            start = date
        case .needsAI, .rejected:
            return
        }
        task.scheduledTime = start
        task.scheduledEndTime = start.addingTimeInterval(TimeInterval(duration * 60))
        task.scheduledDate = day
        if TaskReaper.allowsStart(start, for: task, calendar: calendar) {
            TaskConstraintAlignment.markUserPlaced(&task)
        }
        task.updatedAt = Date()
        tasksByID[taskID] = task
        onTaskUpdated?(task)
        onScheduleDragCommitted?()
    }
}
