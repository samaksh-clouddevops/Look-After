import Foundation

/// Prefers an in-progress task or active Flow session as the hero action.
public struct ContinueTaskRule: FlowSchedulingRuleProtocol {
    public let identifier = "ContinueTaskRule"

    public init() {}

    public func apply(to state: inout MutableSchedulingState, context: FlowSchedulingContext) {
        if let session = context.input.activeFlowSession, session.isActive, let taskID = session.taskID,
           let task = context.activeTasks.first(where: { $0.id == taskID }) {
            state.heroTask = task
            state.actionType = .continue
            state.suggestedDurationMinutes = remainingMinutes(for: task, session: session)
            state.reasoningLines.append("Active Flow session in progress.")
            state.appliedRuleIDs.append(identifier)
            return
        }

        if let inProgress = context.inProgressTask {
            state.heroTask = inProgress
            state.actionType = .continue
            state.suggestedDurationMinutes = FlowTaskSelector.effectiveMinutes(for: inProgress)
            state.reasoningLines.append("In-progress task takes priority.")
            state.appliedRuleIDs.append(identifier)
        }
    }

    private func remainingMinutes(for task: LifeTask, session: FlowSessionState) -> Int {
        let remainingSeconds = max(session.targetSeconds - session.elapsedSeconds, 0)
        let fromSession = max(remainingSeconds / 60, TaskDurationPolicy.minimumMinutes)
        let fromTask = FlowTaskSelector.effectiveMinutes(for: task)
        return min(fromSession, fromTask)
    }
}
