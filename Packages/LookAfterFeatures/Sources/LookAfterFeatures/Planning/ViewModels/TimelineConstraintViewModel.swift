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
    case commitVerticalOffset(taskID: String, offsetMinutes: Int)
}

// MARK: - View model

/// Intent-driven mutation of timeline time constraints. Views must not apply business rules.
@MainActor
public final class TimelineConstraintViewModel: ObservableObject {
    @Published public private(set) var constraintsByTaskID: [String: TimeConstraint] = [:]
    @Published public private(set) var activeDragTaskID: String?
    @Published public private(set) var lastMutation: (taskID: String, constraint: TimeConstraint)?

    private var tasksByID: [String: LifeTask] = [:]
    private let telemetry: any InteractionTelemetryServing
    private let onTaskUpdated: ((LifeTask) -> Void)?

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
        case .endVerticalDrag:
            activeDragTaskID = nil
        case .commitVerticalOffset(let taskID, let offsetMinutes):
            commitScheduleOffset(taskID: taskID, minutes: offsetMinutes)
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

    private func commitScheduleOffset(taskID: String, minutes: Int) {
        guard minutes != 0,
              var task = tasksByID[taskID],
              task.timeConstraintValue != .anchored else {
            return
        }
        let delta = TimeInterval(minutes * 60)
        if let start = task.scheduledTime {
            task.scheduledTime = start.addingTimeInterval(delta)
        }
        if let end = task.scheduledEndTime {
            task.scheduledEndTime = end.addingTimeInterval(delta)
        }
        if let day = task.scheduledDate {
            task.scheduledDate = day.addingTimeInterval(delta)
        }
        task.updatedAt = Date()
        tasksByID[taskID] = task
        onTaskUpdated?(task)
    }
}
