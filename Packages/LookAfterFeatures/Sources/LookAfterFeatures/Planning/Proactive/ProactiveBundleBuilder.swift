import Foundation
import LookAfterCore

/// Builds pre-built apply payloads for high-value proactive kinds.
public enum ProactiveBundleBuilder {

    public static func bundle(for action: ProactiveAction, context: BuildContext) -> ProactiveActionBundle {
        switch action.kind {
        case .emailActionRequired:
            return emailBundle(action: action, context: context)
        case .lifeAdminBatch:
            return lifeAdminBundle(action: action, context: context)
        case .captureResurrection:
            return captureResurrectionBundle(action: action, context: context)
        case .endOfDayClose:
            return endOfDayBundle(action: action, context: context)
        case .relationshipDrift:
            return relationshipDriftBundle(action: action, context: context)
        case .travelDisruption, .calendarChange:
            return variantBundle(action: action, context: context)
        case .waitingMode, .initiationBridge, .deferralRecovery, .postCompletionMomentum:
            return focusMicroStartBundle(action: action, context: context)
        case .badDay:
            return recoveryBundle(context: context)
        default:
            return ProactiveActionBundle()
        }
    }

    public static func enrich(_ actions: [ProactiveAction], context: BuildContext) -> [ProactiveAction] {
        actions.map { action in
            let bundle = bundle(for: action, context: context)
            guard !bundle.mutations.isEmpty || bundle.variant != nil || bundle.focusSessionTaskID != nil || bundle.moduleRoute != nil else {
                return action
            }
            return ProactiveActionBundleCodec.action(action, attaching: bundle)
        }
    }

    public struct BuildContext: Sendable {
        public var tasks: [LifeTask]
        public var inboxItems: [InboxItem]
        public var bills: [BillItem]
        public var now: Date
        public var calendar: Calendar

        public init(
            tasks: [LifeTask] = [],
            inboxItems: [InboxItem] = [],
            bills: [BillItem] = [],
            now: Date = Date(),
            calendar: Calendar = .current
        ) {
            self.tasks = tasks
            self.inboxItems = inboxItems
            self.bills = bills
            self.now = now
            self.calendar = calendar
        }
    }

    private static func emailBundle(action: ProactiveAction, context: BuildContext) -> ProactiveActionBundle {
        let subject = action.metadata["emailSubject"] ?? action.message
        let threadID = action.metadata["threadID"] ?? action.relatedInboxIDs.first ?? ""
        let mutation = PlanMutation(
            kind: .createTask,
            title: "Reply: \(subject)",
            estimatedMinutes: 5,
            priority: .high,
            startHour: context.calendar.component(.hour, from: context.now.addingTimeInterval(15 * 60)),
            startMinute: context.calendar.component(.minute, from: context.now.addingTimeInterval(15 * 60)),
            captureNote: threadID.isEmpty ? nil : "Email thread \(threadID)"
        )
        return ProactiveActionBundle(mutations: [mutation])
    }

    private static func lifeAdminBundle(action: ProactiveAction, context: BuildContext) -> ProactiveActionBundle {
        let taskID = action.relatedTaskIDs.first ?? context.tasks.first(where: { $0.status.isActive })?.id
        var mutations: [PlanMutation] = []
        if let friday = nextFriday(from: context.now, calendar: context.calendar) {
            let hour = context.calendar.component(.hour, from: friday)
            mutations.append(PlanMutation(
                kind: .rescheduleTask,
                taskID: taskID,
                startHour: hour,
                startMinute: 0,
                reason: "Life admin batch"
            ))
        }
        return ProactiveActionBundle(
            mutations: mutations,
            focusSessionTaskID: taskID,
            focusSessionMinutes: 15,
            moduleRoute: "lifeAdmin"
        )
    }

    private static func captureResurrectionBundle(action: ProactiveAction, context: BuildContext) -> ProactiveActionBundle {
        if let inboxID = action.relatedInboxIDs.first,
           let item = context.inboxItems.first(where: { $0.id == inboxID }) {
            let title = String(item.content.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
            return ProactiveActionBundle(mutations: [
                PlanMutation(kind: .createTask, title: title.isEmpty ? "Follow up capture" : title, estimatedMinutes: 5, priority: .medium)
            ])
        }
        return ProactiveActionBundle(moduleRoute: "inbox")
    }

    private static func endOfDayBundle(action: ProactiveAction, context: BuildContext) -> ProactiveActionBundle {
        let openIDs = action.relatedTaskIDs.isEmpty
            ? context.tasks.filter(\.status.isActive).prefix(3).map(\.id)
            : action.relatedTaskIDs
        let mutations = openIDs.map {
            PlanMutation(kind: .deferTask, taskID: $0, deferToTomorrow: true, reason: "End of day close")
        }
        return ProactiveActionBundle(mutations: mutations)
    }

    private static func relationshipDriftBundle(action: ProactiveAction, context: BuildContext) -> ProactiveActionBundle {
        let contactName = action.metadata["contactName"] ?? "Contact"
        let contactID = action.metadata["contactID"]
        return ProactiveActionBundle(mutations: [
            PlanMutation(
                kind: .createTask,
                title: "Call \(contactName)",
                estimatedMinutes: 5,
                priority: .medium,
                captureNote: contactID.map { "contact:\($0)" }
            )
        ])
    }

    private static func variantBundle(action: ProactiveAction, context: BuildContext) -> ProactiveActionBundle {
        let flexible = context.tasks.filter { $0.status.isActive && !$0.isFixedTimeEvent }
        let deferrable = Array(flexible.sorted { $0.priority < $1.priority }.prefix(3))
        let variants = PlanVariantBuilder.buildOfflineVariants(tasks: context.tasks, deferCandidates: deferrable)
        let variant = variants.first(where: { $0.recommended }) ?? variants.first
        return ProactiveActionBundle(variant: variant)
    }

    private static func focusMicroStartBundle(action: ProactiveAction, context: BuildContext) -> ProactiveActionBundle {
        let taskID = action.relatedTaskIDs.first ?? context.tasks.first(where: { $0.status.isActive })?.id
        let task = taskID.flatMap { id in context.tasks.first(where: { $0.id == id }) }
        let minutes: Int
        if let task {
            minutes = TaskDurationPolicy.microStartSessionMinutes(for: task)
        } else if action.kind == .waitingMode {
            minutes = TaskDurationPolicy.softDefaultMinutes
        } else {
            minutes = TaskDurationPolicy.softDefaultMinutes
        }
        return ProactiveActionBundle(focusSessionTaskID: taskID, focusSessionMinutes: minutes)
    }

    private static func recoveryBundle(context: BuildContext) -> ProactiveActionBundle {
        let variant = RecoveryTemplateApplier.apply(template: .minimumViable, tasks: context.tasks, context: nil)
        return ProactiveActionBundle(variant: variant)
    }

    private static func nextFriday(from now: Date, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.weekday = 6
        return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime)
    }
}
