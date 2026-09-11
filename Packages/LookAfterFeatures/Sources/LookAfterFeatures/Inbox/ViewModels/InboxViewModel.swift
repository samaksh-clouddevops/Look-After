import Foundation
import LookAfterCore
import LookAfterAI
import LookAfterData

/// ViewModel for the Universal Inbox.
@MainActor
public final class InboxViewModel: ObservableObject {

    @Published public var items: [InboxItem] = []
    @Published public var unprocessedCount: Int = 0
    @Published public var isLoading: Bool = false
    @Published public var isProcessing: Bool = false
    @Published public var error: String?

    private let inboxRepo: InboxRepository
    private let glm: GLMService
    private var currentUserId: String = ""
    public var onCreateTask: ((InboxTaskDraft) async throws -> Void)?

    public init(inboxRepo: InboxRepository? = nil, glmService: GLMService = .shared) {
        self.inboxRepo = inboxRepo ?? InboxRepository()
        self.glm = glmService
    }

    /// Load all inbox items.
    public func loadItems(userId: String) async {
        currentUserId = userId
        if FreshInstallGuard.isActive {
            resetInMemoryState()
            return
        }
        isLoading = true
        do {
            items = try await inboxRepo.getAll(for: userId)
            unprocessedCount = items.filter { $0.status == .unprocessed || $0.status == .needsReview }.count
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// Route capture through unified CaptureRouter (auto-process).
    public func routeCapture(_ request: CaptureRequest, userId: String) async -> CaptureRouteResult {
        isProcessing = true
        defer { isProcessing = false }

        if CaptureOfflineQueue.shared.shouldDeferRouting {
            CaptureOfflineQueue.shared.enqueue(request, userId: userId)
            let preview = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return CaptureRouteResult(outcome: .queuedOffline(preview: preview))
        }

        let result = await CaptureRouter.shared.route(request, userId: userId)
        await loadItems(userId: userId)
        return result
    }

    /// Process captures queued while offline.
    public func processOfflineCaptureQueue(userId: String) async {
        let results = await CaptureOfflineQueue.shared.processPending(userId: userId) { request, uid in
            await CaptureRouter.shared.route(request, userId: uid)
        }
        if !results.isEmpty {
            await loadItems(userId: userId)
        }
        for result in results {
            NotificationCenter.default.post(
                name: .captureDidRoute,
                object: nil,
                userInfo: [CaptureNotificationKey.result: CaptureRouteResultBox(result)]
            )
        }
    }

    /// Quick capture — routes via CaptureRouter (same as composer).
    public func quickCapture(text: String, userId: String, source: CaptureSource = .inbox) async -> CaptureRouteResult {
        await routeCapture(
            CaptureRequest(text: text, source: source, contextHints: CaptureContextHints(screen: "inbox")),
            userId: userId
        )
    }

    /// Process an inbox item with AI.
    public func processItem(_ item: InboxItem) async {
        isProcessing = true

        let prompt = LookAfterPrompts.inboxProcessingPrompt(item: item)

        do {
            let response = try await glm.complete(
                prompt: prompt,
                systemPrompt: LookAfterPrompts.inboxProcessingSystem,
                tier: .standard
            )

            let cleaned = response
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let data = cleaned.data(using: .utf8),
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {

                var updated = item
                updated.status = .categorized
                updated.aiSummary = json["summary"] as? String
                updated.aiSuggestedAction = json["suggestedAction"] as? String
                updated.processedAt = Date()

                if let areaStr = json["lifeArea"] as? String {
                    updated.lifeArea = LifeArea.allCases.first { $0.rawValue == areaStr }
                }
                if let priorityStr = json["priority"] as? String {
                    updated.suggestedPriority = Priority.allCases.first { $0.label == priorityStr }
                }

                try await inboxRepo.update(updated)

                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index] = updated
                }
                unprocessedCount = items.filter { $0.status == .unprocessed || $0.status == .needsReview }.count

                if let action = json["suggestedAction"] as? String,
                   action.lowercased() != "archive",
                   let title = json["taskTitle"] as? String,
                   !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let handler = onCreateTask {
                    let difficultyStr = json["taskDifficulty"] as? String
                    let difficulty = TaskDifficulty.allCases.first { $0.rawValue == difficultyStr }
                    let minutes = json["estimatedMinutes"] as? Int ?? 15
                    let draft = InboxTaskDraft(
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        lifeArea: updated.lifeArea,
                        priority: updated.suggestedPriority,
                        difficulty: difficulty,
                        estimatedMinutes: TaskDurationPolicy.clamp(minutes, allowShortTasks: true)
                    )
                    try await handler(draft)
                    updated.status = .actionCreated
                    try await inboxRepo.update(updated)
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items[index] = updated
                    }
                }
            }
        } catch {
            self.error = error.localizedDescription
        }

        isProcessing = false
    }

    /// Delete an inbox item.
    public func deleteItem(_ item: InboxItem) async {
        do {
            try await inboxRepo.delete(item.id)
            items.removeAll { $0.id == item.id }
            unprocessedCount = items.filter { $0.status == .unprocessed || $0.status == .needsReview }.count
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Clears inbox presentation state after factory reset.
    public func resetInMemoryState() {
        items = []
        unprocessedCount = 0
        isLoading = false
        isProcessing = false
        error = nil
    }
}
