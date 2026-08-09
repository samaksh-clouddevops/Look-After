import Foundation
import LookAfterCore

/// Applies recovery day templates as plan variants.
public enum RecoveryTemplateApplier {
    public static func apply(
        template: RecoveryDayTemplate,
        tasks: [LifeTask],
        context: DayReplanContext? = nil
    ) -> PlanVariant {
        let flexible = tasks.filter { $0.status.isActive && !$0.isFixedTimeEvent && !$0.isLifeCommitmentTask }
        let changes: [DayReplanScheduleChange]

        switch template {
        case .minimumViable:
            let keep = Set(flexible.sorted { $0.priority > $1.priority }.prefix(3).map(\.id))
            changes = flexible.filter { !keep.contains($0.id) }.map {
                DayReplanScheduleChange(taskID: $0.id, deferToTomorrow: true, reason: "Minimum viable day")
            }
        case .recovery:
            changes = flexible.map {
                DayReplanScheduleChange(taskID: $0.id, deferToTomorrow: true, reason: "Recovery day — rest first")
            }
        case .gentlePush:
            let keep = flexible.sorted { $0.priority > $1.priority }.first
            changes = flexible.filter { $0.id != keep?.id }.map {
                DayReplanScheduleChange(taskID: $0.id, deferToTomorrow: true, reason: "Protect one focus slot")
            }
        }

        if let ctx = context {
            let variants = PlanVariantBuilder.buildOfflineVariants(tasks: tasks, deferCandidates: [], context: ctx)
            if let match = variants.first(where: { $0.label.lowercased().contains(String(template.label.lowercased().prefix(4))) }) {
                return match
            }
        }

        return PlanVariant(
            id: template.rawValue,
            label: template.label,
            summary: template.summary,
            tradeoffs: ["Less done today", "Protects energy"],
            scheduleChanges: changes,
            timelineDeltas: Array(changes.prefix(2)).map { _ in
                PlanningTimelineDelta(timeLabel: "—", title: "Task", change: .removed)
            },
            recommended: true
        )
    }
}
