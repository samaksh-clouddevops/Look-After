import Foundation
import LookAfterCore
import LookAfterAI

public struct EmailThreadSummary: Identifiable, Sendable, Equatable, Codable {
    public var id: String
    public var subject: String
    public var sender: String
    public var snippet: String
    public var receivedAt: Date
    public var isUnread: Bool

    public init(id: String, subject: String, sender: String, snippet: String, receivedAt: Date = Date(), isUnread: Bool = true) {
        self.id = id
        self.subject = subject
        self.sender = sender
        self.snippet = snippet
        self.receivedAt = receivedAt
        self.isUnread = isUnread
    }
}

public enum EmailTriageAction: String, Sendable, Codable {
    case reply
    case task
    case deferAction
    case ignore
    case lifeAdmin
}

public struct EmailTriageItem: Identifiable, Sendable, Equatable {
    public var id: String
    public var thread: EmailThreadSummary
    public var action: EmailTriageAction
    public var draftSummary: String
    public var urgency: ProactiveAction.Severity

    public init(id: String = UUID().uuidString, thread: EmailThreadSummary, action: EmailTriageAction, draftSummary: String, urgency: ProactiveAction.Severity = .medium) {
        self.id = id
        self.thread = thread
        self.action = action
        self.draftSummary = draftSummary
        self.urgency = urgency
    }
}

/// Syncs unread Gmail threads via auth proxy or local mock for development.
public final class GmailSyncService {
    public static let shared = GmailSyncService()

    public init() {}

    public func fetchUnreadThreads(limit: Int = 20) async throws -> [EmailThreadSummary] {
        guard GmailOAuthService.isEnabled else { return [] }
        // Proxy Gmail API passthrough — falls back to seeded threads until Azure /gmail route ships.
        return mockThreads().prefix(limit).map { $0 }
    }

    private func mockThreads() -> [EmailThreadSummary] {
        [
            EmailThreadSummary(id: "mock-1", subject: "Invoice due Friday", sender: "billing@utility.com", snippet: "Your electric bill is due..."),
            EmailThreadSummary(id: "mock-2", subject: "Flight confirmation", sender: "airline@travel.com", snippet: "Flight AA123 departs 6am...")
        ]
    }
}

/// LLM classifies email threads into actionable categories.
public enum EmailTriageClassifier {
    public static func classify(threads: [EmailThreadSummary], glm: GLMService = .shared) async -> [EmailTriageItem] {
        guard !threads.isEmpty else { return [] }
        var items: [EmailTriageItem] = []
        for thread in threads {
            items.append(await classifyOne(thread, glm: glm))
        }
        return items
    }

    private static func classifyOne(_ thread: EmailThreadSummary, glm: GLMService) async -> EmailTriageItem {
        let prompt = """
        Classify this email for an ADHD user. Return JSON only:
        {"action":"reply|task|defer|ignore|lifeAdmin","draftSummary":"one line","urgency":"low|medium|high"}
        Subject: \(thread.subject)
        From: \(thread.sender)
        Snippet: \(thread.snippet)
        """
        do {
            let raw = try await glm.sendMessage(prompt, systemPrompt: "Return only JSON.", history: [], tier: .standard)
            if let item = parse(raw, thread: thread) { return item }
        } catch {
            print("[EmailTriage] \(error.localizedDescription)")
        }
        return heuristic(thread)
    }

    private static func parse(_ raw: String, thread: EmailThreadSummary) -> EmailTriageItem? {
        let clean = raw.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        guard let start = clean.firstIndex(of: "{"), let end = clean.lastIndex(of: "}"),
              let data = String(clean[start...end]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let actionRaw = json["action"] as? String else { return nil }
        let action: EmailTriageAction
        switch actionRaw.lowercased() {
        case "reply": action = .reply
        case "task": action = .task
        case "defer": action = .deferAction
        case "lifeadmin", "life_admin": action = .lifeAdmin
        default: action = .ignore
        }
        let urgencyRaw = (json["urgency"] as? String) ?? "medium"
        let urgency = ProactiveAction.Severity(rawValue: urgencyRaw) ?? .medium
        return EmailTriageItem(
            thread: thread,
            action: action,
            draftSummary: json["draftSummary"] as? String ?? thread.snippet,
            urgency: urgency
        )
    }

    private static func heuristic(_ thread: EmailThreadSummary) -> EmailTriageItem {
        let lower = (thread.subject + thread.snippet).lowercased()
        let action: EmailTriageAction
        if lower.contains("flight") || lower.contains("confirmation") { action = .task }
        else if lower.contains("bill") || lower.contains("invoice") { action = .lifeAdmin }
        else if lower.contains("re:") { action = .reply }
        else { action = .deferAction }
        return EmailTriageItem(thread: thread, action: action, draftSummary: thread.snippet)
    }

    public static func proactiveActions(from items: [EmailTriageItem]) -> [ProactiveAction] {
        items.filter { $0.action != .ignore && $0.urgency != .low }.prefix(3).map { item in
            ProactiveAction(
                id: "email-\(item.thread.id)",
                kind: .emailActionRequired,
                severity: item.urgency,
                message: "Email: \(item.thread.subject) — \(item.draftSummary)",
                options: ["Create task", "Reply later", "Dismiss"],
                surface: .banner,
                metadata: ["threadId": item.thread.id, "action": item.action.rawValue]
            )
        }
    }
}

public actor EmailTriageStore {
    public static let shared = EmailTriageStore()
    private var items: [EmailTriageItem] = []

    public func replaceAll(_ newItems: [EmailTriageItem]) {
        items = newItems
    }

    public func all() -> [EmailTriageItem] { items }
}
