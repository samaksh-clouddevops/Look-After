import Foundation
import LookAfterCore
import LookAfterData
import LookAfterAI

@MainActor
public final class CaptureRouter {
    public static let shared = CaptureRouter()

    public var onCreateTask: ((InboxTaskDraft, String?) async throws -> LifeTask)?
    public var onCreateScheduledTask: ((InboxTaskDraft, Date, String?) async throws -> LifeTask)?
    public var onJournalEntry: ((String, String) async throws -> String)?
    public var onHealthLog: ((String, String?, String) async throws -> Void)?
    public var onInboxItemsChanged: (() async -> Void)?

    private let inboxRepo = InboxRepository()
    private let glm = GLMService.shared

    private init() {}

    public func route(_ request: CaptureRequest, userId: String) async -> CaptureRouteResult {
        let trimmed = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return CaptureRouteResult(outcome: .archived)
        }

        var inboxItem = InboxItem(
            content: trimmed,
            type: request.voiceTranscript ? .voiceMemo : .text,
            status: .processing,
            userId: userId
        )
        do {
            try await inboxRepo.create(inboxItem)
        } catch {
            return CaptureRouteResult(outcome: .needsReview(inboxId: inboxItem.id, preview: trimmed))
        }

        let decision = await CaptureIntentClassifier.classify(request: request, glm: glm)

        if decision.intent == .auto && decision.confidence >= 0.85 {
            inboxItem.status = .archived
            inboxItem.processedAt = Date()
            inboxItem.aiSummary = decision.summary
            try? await inboxRepo.update(inboxItem)
            await onInboxItemsChanged?()
            postNotification(CaptureRouteResult(outcome: .archived, inboxItemId: inboxItem.id))
            return CaptureRouteResult(outcome: .archived, inboxItemId: inboxItem.id)
        }

        if decision.confidence < 0.55 {
            inboxItem.status = .needsReview
            inboxItem.aiSummary = decision.summary
            inboxItem.processedAt = Date()
            try? await inboxRepo.update(inboxItem)
            await onInboxItemsChanged?()
            let result = CaptureRouteResult(
                outcome: .needsReview(inboxId: inboxItem.id, preview: trimmed),
                inboxItemId: inboxItem.id
            )
            postNotification(result)
            return result
        }

        switch decision.intent {
        case .task:
            return await routeTask(decision: decision, inboxItem: inboxItem, userId: userId, preview: trimmed)
        case .event:
            return await routeEvent(decision: decision, inboxItem: inboxItem, userId: userId, preview: trimmed, hints: request.contextHints)
        case .note, .insight:
            return await routeJournal(decision: decision, inboxItem: inboxItem, preview: trimmed, asInsight: decision.intent == .insight)
        case .mood:
            return await routeMood(decision: decision, inboxItem: inboxItem, userId: userId, preview: trimmed, hints: request.contextHints)
        case .auto:
            return await routeTask(decision: decision, inboxItem: inboxItem, userId: userId, preview: trimmed)
        }
    }

    public func undoTask(taskId: String, inboxItemId: String?, userId: String, taskRepo: TaskRepository) async {
        try? await taskRepo.delete(taskId)
        if let inboxItemId {
            try? await inboxRepo.delete(inboxItemId)
        }
        NotificationCenter.default.post(name: .taskListDidChange, object: nil)
        await onInboxItemsChanged?()
    }

    // MARK: - Handlers

    private func routeTask(
        decision: CaptureRoutingDecision,
        inboxItem: InboxItem,
        userId: String,
        preview: String
    ) async -> CaptureRouteResult {
        let title = (decision.title ?? preview).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let handler = onCreateTask else {
            return await fallbackReview(inboxItem: inboxItem, preview: preview)
        }

        let draft = InboxTaskDraft(
            title: title,
            lifeArea: decision.lifeArea,
            priority: decision.priority,
            difficulty: decision.difficulty,
            estimatedMinutes: TaskDurationPolicy.clamp(decision.estimatedMinutes ?? 15, allowShortTasks: true)
        )

        do {
            let task = try await handler(draft, inboxItem.id)
            var updated = inboxItem
            updated.status = .actionCreated
            updated.aiSummary = decision.summary ?? title
            updated.processedAt = Date()
            try? await inboxRepo.update(updated)
            await onInboxItemsChanged?()
            let result = CaptureRouteResult(
                outcome: .taskCreated(taskId: task.id, title: task.title),
                inboxItemId: inboxItem.id,
                createdTaskId: task.id
            )
            postNotification(result)
            await CaptureGraphIndexer.indexTask(inboxID: inboxItem.id, taskID: task.id)
            return result
        } catch {
            return await fallbackReview(inboxItem: inboxItem, preview: preview)
        }
    }

    private func routeEvent(
        decision: CaptureRoutingDecision,
        inboxItem: InboxItem,
        userId: String,
        preview: String,
        hints: CaptureContextHints
    ) async -> CaptureRouteResult {
        let title = (decision.title ?? preview).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return await fallbackReview(inboxItem: inboxItem, preview: preview)
        }
        let scheduledAt = decision.scheduledAt ?? hints.preselectedDate ?? Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()

        let draft = InboxTaskDraft(
            title: title,
            lifeArea: decision.lifeArea ?? .personal,
            priority: decision.priority ?? .medium,
            difficulty: decision.difficulty ?? .easy,
            estimatedMinutes: TaskDurationPolicy.clamp(decision.durationMinutes ?? decision.estimatedMinutes ?? 30, allowShortTasks: true)
        )

        do {
            let task: LifeTask
            if let scheduledHandler = onCreateScheduledTask {
                task = try await scheduledHandler(draft, scheduledAt, inboxItem.id)
            } else if let handler = onCreateTask {
                task = try await handler(draft, inboxItem.id)
            } else {
                return await fallbackReview(inboxItem: inboxItem, preview: preview)
            }
            var updated = inboxItem
            updated.status = .actionCreated
            updated.aiSummary = decision.summary ?? title
            updated.processedAt = Date()
            try? await inboxRepo.update(updated)
            await onInboxItemsChanged?()
            let result = CaptureRouteResult(
                outcome: .scheduledEvent(taskId: task.id, title: task.title, scheduledAt: scheduledAt),
                inboxItemId: inboxItem.id,
                createdTaskId: task.id
            )
            postNotification(result)
            await CaptureGraphIndexer.indexTask(inboxID: inboxItem.id, taskID: task.id)
            return result
        } catch {
            return await fallbackReview(inboxItem: inboxItem, preview: preview)
        }
    }

    private func routeJournal(
        decision: CaptureRoutingDecision,
        inboxItem: InboxItem,
        preview: String,
        asInsight: Bool
    ) async -> CaptureRouteResult {
        let content = decision.summary ?? preview
        if let handler = onJournalEntry {
            do {
                let entryId = try await handler(content, asInsight ? "Insight" : "Reflective")
                var updated = inboxItem
                updated.status = .actionCreated
                updated.aiSummary = decision.summary ?? content
                updated.processedAt = Date()
                try? await inboxRepo.update(updated)
                await onInboxItemsChanged?()
                let outcome: CaptureOutcome = asInsight
                    ? .insightSaved(inboxId: inboxItem.id, preview: content)
                    : .journalEntry(id: entryId, preview: content)
                let result = CaptureRouteResult(outcome: outcome, inboxItemId: inboxItem.id)
                postNotification(result)
                await CaptureGraphIndexer.indexJournal(inboxID: inboxItem.id, entryID: entryId)
                return result
            } catch {
                return await fallbackReview(inboxItem: inboxItem, preview: preview)
            }
        }
        var updated = inboxItem
        updated.status = .actionCreated
        updated.aiSummary = content
        updated.processedAt = Date()
        try? await inboxRepo.update(updated)
        await onInboxItemsChanged?()
        let result = CaptureRouteResult(
            outcome: .insightSaved(inboxId: inboxItem.id, preview: content),
            inboxItemId: inboxItem.id
        )
        postNotification(result)
        return result
    }

    private func routeMood(
        decision: CaptureRoutingDecision,
        inboxItem: InboxItem,
        userId: String,
        preview: String,
        hints: CaptureContextHints
    ) async -> CaptureRouteResult {
        let mood = decision.moodLabel ?? CaptureIntentClassifier.parseDecision(from: preview, fallbackText: preview)?.moodLabel ?? "Okay"
        let note = preview
        if let handler = onHealthLog {
            do {
                try await handler(mood, note, userId)
                var updated = inboxItem
                updated.status = .actionCreated
                updated.aiSummary = "Mood: \(mood)"
                updated.processedAt = Date()
                try? await inboxRepo.update(updated)
                await onInboxItemsChanged?()
                let result = CaptureRouteResult(outcome: .healthLog(mood: mood, note: note), inboxItemId: inboxItem.id)
                postNotification(result)
                return result
            } catch {
                return await fallbackReview(inboxItem: inboxItem, preview: preview)
            }
        }
        return await fallbackReview(inboxItem: inboxItem, preview: preview)
    }

    private func fallbackReview(inboxItem: InboxItem, preview: String) async -> CaptureRouteResult {
        var updated = inboxItem
        updated.status = .needsReview
        updated.processedAt = Date()
        try? await inboxRepo.update(updated)
        await onInboxItemsChanged?()
        let result = CaptureRouteResult(
            outcome: .needsReview(inboxId: inboxItem.id, preview: preview),
            inboxItemId: inboxItem.id
        )
        postNotification(result)
        return result
    }

    private func postNotification(_ result: CaptureRouteResult) {
        NotificationCenter.default.post(
            name: .captureDidRoute,
            object: nil,
            userInfo: [CaptureNotificationKey.result: CaptureRouteResultBox(result)]
        )
    }
}
