import Foundation
import LookAfterCore

/// Builds deterministic 2–3 plan variants for negotiation and replan previews.
public enum PlanVariantBuilder {

    public static func buildOfflineVariants(
        tasks: [LifeTask],
        deferCandidates: [LifeTask],
        context: DayReplanContext? = nil
    ) -> [PlanVariant] {
        let flexible = tasks.filter { $0.status.isActive && !$0.isFixedTimeEvent && !$0.isLifeCommitmentTask }
        let deferrable = deferCandidates.isEmpty
            ? Array(flexible.sorted { $0.priority < $1.priority }.prefix(3))
            : deferCandidates

        var variants: [PlanVariant] = []

        // Variant A: Protect fixed / deep work — defer low-priority flexible
        let protectChanges = deferrable.map {
            DayReplanScheduleChange(taskID: $0.id, deferToTomorrow: true, reason: "Protect focus time")
        }
        variants.append(PlanVariant(
            id: "protect-focus",
            label: "Protect deep work",
            summary: "Keep fixed commitments and defer \(deferrable.count) flexible item\(deferrable.count == 1 ? "" : "s") to tomorrow.",
            tradeoffs: ["Less done today", "Better focus on what matters"],
            scheduleChanges: protectChanges,
            timelineDeltas: deferrable.prefix(2).map {
                PlanningTimelineDelta(timeLabel: "—", title: $0.title, change: .removed)
            },
            recommended: true
        ))

        // Variant B: Minimum viable — keep top 2 by priority
        let keep = Array(flexible.sorted { $0.priority > $1.priority }.prefix(2))
        let keepIDs = Set(keep.map(\.id))
        let minimumChanges = flexible.filter { !keepIDs.contains($0.id) }.map {
            DayReplanScheduleChange(taskID: $0.id, deferToTomorrow: true, reason: "Minimum viable day")
        }
        variants.append(PlanVariant(
            id: "minimum-viable",
            label: "Minimum viable",
            summary: "Focus on \(keep.count) top priorities; defer the rest.",
            tradeoffs: ["Smallest cognitive load", "Some tasks slip"],
            scheduleChanges: minimumChanges,
            timelineDeltas: keep.prefix(2).map {
                PlanningTimelineDelta(timeLabel: "—", title: $0.title, change: .unchanged)
            },
            recommended: false
        ))

        // Variant C: Reschedule flexible — try to fit remaining work
        if let ctx = context {
            let rescheduled = localRescheduleChanges(context: ctx, tasks: flexible.prefix(4).map { $0 })
            if !rescheduled.isEmpty {
                variants.append(PlanVariant(
                    id: "reshuffle",
                    label: "Reshuffle afternoon",
                    summary: "Move flexible work into open slots without dropping fixed items.",
                    tradeoffs: ["More context switching", "Nothing deferred if slots fit"],
                    scheduleChanges: rescheduled,
                    timelineDeltas: rescheduled.prefix(2).map { change in
                        let title = tasks.first { $0.id == change.taskID }?.title ?? "Task"
                        return PlanningTimelineDelta(timeLabel: "—", title: title, change: .moved)
                    },
                    recommended: false
                ))
            }
        }

        return Array(variants.prefix(3))
    }

    public static func buildOfflinePlanningVariants(
        context: PlanningConversationContext,
        deferCandidates: [LifeTask]
    ) -> [PlanVariant] {
        let replanContext = DayReplanContext(planningContext: context, completedTasks: [])
        return buildOfflineVariants(
            tasks: context.tasks,
            deferCandidates: deferCandidates,
            context: replanContext
        )
    }

    public static func negotiation(from variants: [PlanVariant], question: String) -> PlanningNegotiation {
        PlanningNegotiation(
            question: question,
            options: variants.map(\.label),
            optionVariantIDs: variants.map(\.id)
        )
    }

    public static func result(from variant: PlanVariant, fallbackSummary: String? = nil) -> DayReplanResult {
        DayReplanResult(
            summary: variant.summary.isEmpty ? (fallbackSummary ?? variant.label) : variant.summary,
            scheduleChanges: variant.scheduleChanges,
            mutations: [],
            timelineDeltas: variant.timelineDeltas,
            planVariants: nil,
            recommendedVariantID: variant.id
        )
    }

    private static func localRescheduleChanges(context: DayReplanContext, tasks: [LifeTask]) -> [DayReplanScheduleChange] {
        let calendar = Calendar.current
        let now = Date()
        let day = calendar.startOfDay(for: now)
        let workHours = PlanningSchedulePolicy.WorkHours.from(profile: context.planningContext.lifeProfile)
        var slot = PlanningSchedulePolicy.nextAvailableSlot(workHours: workHours) ?? (workHours.startHour, 0)
        var slotDate = calendar.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: day) ?? now
        var changes: [DayReplanScheduleChange] = []

        for task in tasks {
            while slotDate < now {
                slot = (min(slot.hour + 1, workHours.endHour), slot.minute)
                slotDate = calendar.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: day) ?? slotDate.addingTimeInterval(3600)
            }
            changes.append(DayReplanScheduleChange(
                taskID: task.id,
                startHour: slot.hour,
                startMinute: slot.minute,
                reason: "Fits in open slot"
            ))
            slot = (min(slot.hour + 1, workHours.endHour), slot.minute)
            slotDate = calendar.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: day) ?? slotDate.addingTimeInterval(3600)
        }
        return changes
    }
}
