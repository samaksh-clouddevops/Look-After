import Foundation
import LookAfterCore
import LookAfterFeatures

/// Unified handler for proactive banner and notification options.
@MainActor
struct ProactiveActionRouter {

    struct Environment {
        var shell: AppShellState
        var planningVM: ExecutivePlanningViewModel
        var userId: String
        var planningContext: () -> PlanningConversationContext
        var refreshContext: () async -> Void
        var startFocusSession: (LifeTask, Int) -> Void
        var showModules: () -> Void
        var triggerCalendarReplan: () async -> Void
        var applyRecoveryTemplate: (String) async -> Void
        var submitPlanningNegotiation: (String) async -> Void
        var shareAccountabilityMessage: (String) -> Void

        init(
            shell: AppShellState,
            planningVM: ExecutivePlanningViewModel,
            userId: String,
            planningContext: @escaping () -> PlanningConversationContext,
            refreshContext: @escaping () async -> Void,
            startFocusSession: @escaping (LifeTask, Int) -> Void,
            showModules: @escaping () -> Void,
            triggerCalendarReplan: @escaping () async -> Void,
            applyRecoveryTemplate: @escaping (String) async -> Void,
            submitPlanningNegotiation: @escaping (String) async -> Void,
            shareAccountabilityMessage: @escaping (String) -> Void
        ) {
            self.shell = shell
            self.planningVM = planningVM
            self.userId = userId
            self.planningContext = planningContext
            self.refreshContext = refreshContext
            self.startFocusSession = startFocusSession
            self.showModules = showModules
            self.triggerCalendarReplan = triggerCalendarReplan
            self.applyRecoveryTemplate = applyRecoveryTemplate
            self.submitPlanningNegotiation = submitPlanningNegotiation
            self.shareAccountabilityMessage = shareAccountabilityMessage
        }
    }

    enum Outcome {
        case handled
        case fallbackToPlanning
        case dismissed
    }

    static func handle(option: String, action: ProactiveAction?, env: Environment) async -> Outcome {
        let lower = option.lowercased()
        let resolvedAction = action ?? env.shell.proactiveActions.first

        if isDismissOption(lower) {
            if let resolvedAction {
                ProactiveFeedbackStore.record(kind: resolvedAction.kind, outcome: .dismissed)
                ProactiveDismissStore.dismissKindForToday(kind: resolvedAction.kind)
                if resolvedAction.kind == .initiationBridge {
                    AppForegroundTracker.reset()
                }
                env.shell.removeProactiveAction(resolvedAction)
            }
            env.shell.clearPendingCalendarChange()
            return .dismissed
        }

        if isSnoozeOption(lower), let resolvedAction {
            ProactiveFeedbackStore.record(kind: resolvedAction.kind, outcome: .snoozed)
            ProactiveDismissStore.snooze(kind: resolvedAction.kind, until: Date().addingTimeInterval(15 * 60))
            if resolvedAction.kind == .initiationBridge {
                AppForegroundTracker.reset()
            }
            env.shell.removeProactiveAction(resolvedAction)
            return .dismissed
        }

        if lower.contains("emergency mode") {
            env.shell.adhdVM.activateEmergencyMode(allTasks: env.shell.tasksVM.tasks)
            recordAccepted(resolvedAction)
            return .handled
        }

        if lower.contains("preview replan") || (lower.contains("replan") && env.shell.pendingCalendarChange != nil) {
            await env.triggerCalendarReplan()
            recordAccepted(resolvedAction)
            return .handled
        }

        if lower.contains("accountability") || lower.contains("ping accountability") {
            let buddy = UserDefaults.standard.string(forKey: AccountabilitySettings.contactNameKey) ?? "my accountability buddy"
            let minutes = resolvedAction.flatMap { action -> Int? in
                guard let id = action.relatedTaskIDs.first,
                      let task = env.shell.tasksVM.tasks.first(where: { $0.id == id }) else { return nil }
                return TaskDurationPolicy.microStartSessionMinutes(for: task)
            } ?? TaskDurationPolicy.softDefaultMinutes
            env.shareAccountabilityMessage("Hey \(buddy) — starting a \(minutes)-min focus block now. Check in on me?")
            recordAccepted(resolvedAction)
            return .handled
        }

        let bundle = resolvedAction.flatMap { ProactiveActionBundleCodec.decode(from: $0) }
            ?? resolvedAction.map {
                ProactiveBundleBuilder.bundle(for: $0, context: buildContext(env: env))
            }

        if let bundle {
            if await applyBundle(bundle, option: option, action: resolvedAction, env: env) {
                recordAccepted(resolvedAction)
                if let resolvedAction { env.shell.removeProactiveAction(resolvedAction) }
                return .handled
            }
        }

        if lower.contains("apply minimum") || lower.contains("apply recovery") || lower.contains("apply gentle") {
            await env.applyRecoveryTemplate(option)
            recordAccepted(resolvedAction)
            if let resolvedAction { env.shell.removeProactiveAction(resolvedAction) }
            return .handled
        }

        if lower.contains("life-admin") || lower.contains("min block") || lower.contains("open plan") {
            env.showModules()
            recordAccepted(resolvedAction)
            return .handled
        }

        await env.submitPlanningNegotiation(option)
        return .fallbackToPlanning
    }

    private static func applyBundle(_ bundle: ProactiveActionBundle, option: String, action: ProactiveAction?, env: Environment) async -> Bool {
        let lower = option.lowercased()

        if lower.contains("min focus")
            || lower.contains("micro-start")
            || (lower.contains("start") && lower.contains("min")) {
            let parsed = TaskDurationPolicy.parseExplicitMinutes(from: option)
            let minutes = bundle.focusSessionMinutes
                ?? parsed
                ?? resolveFocusTask(bundle: bundle, action: action, env: env).map {
                    TaskDurationPolicy.microStartSessionMinutes(for: $0)
                }
                ?? TaskDurationPolicy.softDefaultMinutes
            if let task = resolveFocusTask(bundle: bundle, action: action, env: env) {
                env.startFocusSession(task, minutes)
                return true
            }
        }

        if let variant = bundle.variant,
           lower.contains("preview") || lower.contains("apply") || lower.contains("replan") || lower.contains("variant") || action?.surface == .autoApplyPreview {
            await env.planningVM.applySelectedVariant(
                variant,
                context: env.planningContext(),
                tasksVM: env.shell.tasksVM,
                modulesVM: env.shell.modulesVM,
                userId: env.userId,
                refreshContext: env.refreshContext
            )
            return true
        }

        if !bundle.mutations.isEmpty,
           lower.contains("schedule") || lower.contains("defer") || lower.contains("reschedule") || lower.contains("mark done") || lower.contains("create") || lower.contains("batch") || lower.contains("reply") || lower.contains("call") {
            var medications = MedicationStore.load()
            _ = await PlanMutationApplier().apply(
                mutations: bundle.mutations,
                tasksVM: env.shell.tasksVM,
                modulesVM: env.shell.modulesVM,
                userId: env.userId,
                medications: &medications,
                lifeProfile: UserLifeProfileStore.load(),
                allowUserPlacedOverride: true
            )
            MedicationStore.save(medications)
            await env.refreshContext()
            return true
        }

        if let route = bundle.moduleRoute {
            if route == "lifeAdmin" || route == "inbox" {
                env.showModules()
                return true
            }
        }

        if lower.contains("start") || lower.contains("focus") {
            if let task = resolveFocusTask(bundle: bundle, action: action, env: env) {
                env.startFocusSession(task, bundle.focusSessionMinutes ?? 5)
                return true
            }
        }

        return false
    }

    private static func resolveFocusTask(bundle: ProactiveActionBundle, action: ProactiveAction?, env: Environment) -> LifeTask? {
        if let id = bundle.focusSessionTaskID,
           let task = env.shell.tasksVM.tasks.first(where: { $0.id == id }) {
            return task
        }
        if let id = action?.relatedTaskIDs.first,
           let task = env.shell.tasksVM.tasks.first(where: { $0.id == id }) {
            return task
        }
        return env.shell.brainVM.flowSurface?.heroTask
            ?? env.shell.brainVM.topTasks.first
            ?? env.shell.tasksVM.tasks.first(where: { $0.status.isActive })
    }

    private static func buildContext(env: Environment) -> ProactiveBundleBuilder.BuildContext {
        ProactiveBundleBuilder.BuildContext(
            tasks: env.shell.tasksVM.schedulingContext,
            inboxItems: env.shell.inboxVM.items,
            bills: env.shell.modulesVM.bills,
            now: Date()
        )
    }

    private static func isDismissOption(_ lower: String) -> Bool {
        lower.contains("keep plan") || lower.contains("not now") || lower.contains("already") || lower.contains("dismiss") || lower.contains("skip") || lower.contains("i'm ready")
    }

    private static func isSnoozeOption(_ lower: String) -> Bool {
        lower.contains("snooze")
    }

    private static func recordAccepted(_ action: ProactiveAction?) {
        guard let action else { return }
        ProactiveFeedbackStore.record(kind: action.kind, outcome: .accepted)
    }
}

enum AccountabilitySettings {
    static let contactNameKey = "lookafter.accountability.contactName"
    static let preferredWindowKey = "lookafter.accountability.preferredWindow"
}

enum ProactivePreviewTimeoutStore {
    private static let key = "lookafter.proactive.preview_timeout"

    struct PendingPreview: Codable, Equatable {
        var actionID: String
        var kind: String
        var expiresAt: Date
        var bundleJSON: String?
    }

    static func save(action: ProactiveAction, bundle: ProactiveActionBundle, expiresAt: Date) {
        let payload = PendingPreview(
            actionID: action.id,
            kind: action.kind.rawValue,
            expiresAt: expiresAt,
            bundleJSON: ProactiveActionBundleCodec.decode(from: action).flatMap { _ in action.metadata[ProactiveBundleMetadataKeys.payload] }
        )
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> PendingPreview? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(PendingPreview.self, from: data) else { return nil }
        return decoded
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
