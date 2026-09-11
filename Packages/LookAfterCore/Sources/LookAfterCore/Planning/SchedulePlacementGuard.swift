import Foundation

/// Single allow / snap / reject path for planner, AI, and timeline drag.
public enum SchedulePlacementGuard {
    public enum Mode: Sendable {
        /// Allocator search — stay inside the bounding box, snap off occupancy.
        case searchInBox
        /// User / AI drop — reject starts outside the fence instead of clamping to 17:00.
        case rejectOutsideBox
    }

    public enum Placement: Equatable, Sendable {
        case accepted(Date)
        case snapped(Date)
        case rejected(String)
        /// Semantics cannot decide. Drag may keep the clock; system commits should ask the LLM.
        case needsAI(String, proposed: Date)
    }

    public static func workHours(forBox box: TemporalBoundingBox) -> PlanningSchedulePolicy.WorkHours {
        PlanningSchedulePolicy.WorkHours(
            startHour: box.earliestStartHour,
            startMinute: 0,
            endHour: min(23, box.latestStartHour),
            endMinute: 59
        )
    }

    public static func evaluate(
        proposedStart: Date,
        durationMinutes: Int,
        task: LifeTask,
        occupied: [TaskScheduleInterval],
        calendar: Calendar = .current,
        mode: Mode = .rejectOutsideBox,
        neighborTasks: [LifeTask] = [],
        dayEnd: Date? = nil
    ) -> Placement {
        let day = calendar.startOfDay(for: task.scheduledDate ?? proposedStart)
        guard let start = calendar.combine(date: day, timeFrom: proposedStart) else {
            return .rejected("Could not combine date and time")
        }
        let duration = max(durationMinutes, TaskDurationPolicy.minimumMinutes)
        let end = start.addingTimeInterval(TimeInterval(duration * 60))
        let box = TaskEphemeralityDefaults.boundingBox(for: task)

        if let box {
            switch mode {
            case .rejectOutsideBox:
                guard box.contains(start: start, calendar: calendar) else {
                    return .rejected("Outside time fence")
                }
            case .searchInBox:
                if let clamped = box.clampStart(start, on: day, calendar: calendar),
                   clamped != start {
                    return evaluate(
                        proposedStart: clamped,
                        durationMinutes: duration,
                        task: task,
                        occupied: occupied,
                        calendar: calendar,
                        mode: .searchInBox,
                        neighborTasks: neighborTasks,
                        dayEnd: dayEnd
                    )
                }
                guard box.contains(start: start, calendar: calendar) else {
                    return .rejected("Outside time fence")
                }
            }
        }

        let probe = TaskScheduleInterval(taskID: task.id, start: start, end: end)
        if let conflict = occupied.first(where: { $0.taskID != task.id && probe.overlaps($0) }) {
            let snapped = conflict.end
            if mode == .rejectOutsideBox, let box, !box.contains(start: snapped, calendar: calendar) {
                return .rejected("Overlaps a protected block")
            }
            if abs(snapped.timeIntervalSince(start)) < 1 {
                return .rejected("Overlaps a protected block")
            }
            return evaluate(
                proposedStart: snapped,
                durationMinutes: duration,
                task: task,
                occupied: occupied,
                calendar: calendar,
                mode: mode,
                neighborTasks: neighborTasks,
                dayEnd: dayEnd
            )
        }

        let sense = SemanticPlacementSense.judge(
            SemanticPlacementSense.Input(
                task: task,
                proposedStart: start,
                durationMinutes: duration,
                occupied: occupied,
                neighborTasks: neighborTasks,
                calendar: calendar,
                dayEnd: dayEnd
            )
        )
        switch sense {
        case .makesSense:
            break
        case .doesNotMakeSense(let reason):
            return .rejected(reason)
        case .needsAI(let reason):
            if mode == .searchInBox {
                return .rejected(reason)
            }
            return .needsAI(reason, proposed: start)
        }

        if abs(start.timeIntervalSince(proposedStart)) > 30 {
            return .snapped(start)
        }
        return .accepted(start)
    }
}
