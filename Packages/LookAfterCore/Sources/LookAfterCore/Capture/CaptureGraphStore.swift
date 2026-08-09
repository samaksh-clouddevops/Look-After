import Foundation
import LookAfterCore

public enum CaptureGraphNodeKind: String, Codable, Sendable {
    case inbox
    case task
    case bill
    case journal
    case memory
    case contact
    case shopping
}

public struct CaptureGraphEdge: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sourceInboxID: String
    public var targetEntityID: String
    public var targetKind: CaptureGraphNodeKind
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        sourceInboxID: String,
        targetEntityID: String,
        targetKind: CaptureGraphNodeKind,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceInboxID = sourceInboxID
        self.targetEntityID = targetEntityID
        self.targetKind = targetKind
        self.createdAt = createdAt
    }
}

/// In-memory + persisted capture → entity graph.
public actor CaptureGraphStore {
    public static let shared = CaptureGraphStore()

    private var edges: [CaptureGraphEdge] = []
    private let storageKey = "capture_graph_edges"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? SharedFormatters.jsonDecoderSeconds.decode([CaptureGraphEdge].self, from: data) {
            edges = decoded
        }
    }

    public func record(sourceInboxID: String, targetEntityID: String, targetKind: CaptureGraphNodeKind) async {
        guard !edges.contains(where: { $0.sourceInboxID == sourceInboxID && $0.targetEntityID == targetEntityID }) else { return }
        edges.append(CaptureGraphEdge(sourceInboxID: sourceInboxID, targetEntityID: targetEntityID, targetKind: targetKind))
        persist()
    }

    public func removeEdges(forInboxID inboxID: String) async {
        edges.removeAll { $0.sourceInboxID == inboxID }
        persist()
    }

    public func edges(fromInboxID inboxID: String) async -> [CaptureGraphEdge] {
        edges.filter { $0.sourceInboxID == inboxID }
    }

    public func allEdges() async -> [CaptureGraphEdge] {
        edges
    }

    private func persist() {
        if let data = try? SharedFormatters.jsonEncoderSeconds.encode(edges) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

public enum CaptureGraphIndexer {
    public static func indexTask(inboxID: String, taskID: String) async {
        await CaptureGraphStore.shared.record(sourceInboxID: inboxID, targetEntityID: taskID, targetKind: .task)
    }

    public static func indexJournal(inboxID: String, entryID: String) async {
        await CaptureGraphStore.shared.record(sourceInboxID: inboxID, targetEntityID: entryID, targetKind: .journal)
    }

    public static func indexMemory(inboxID: String, memoryID: String) async {
        await CaptureGraphStore.shared.record(sourceInboxID: inboxID, targetEntityID: memoryID, targetKind: .memory)
    }
}
