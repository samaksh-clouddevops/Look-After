import Foundation

// MARK: - Chat types (used by GLMService and Executive Brain)

/// A chat message for conversation history.
public struct ChatMessage: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var role: ChatRole
    public var content: String
    public var timestamp: Date
    
    public init(
        id: String = UUID().uuidString,
        role: ChatRole,
        content: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

public enum ChatRole: String, Codable, Sendable {
    case user = "user"
    case assistant = "model"
    case system = "system"
}

// MARK: - Repository Protocols

/// Generic async repository for CRUD operations.
public protocol Repository {
    associatedtype T: Identifiable & Codable & Sendable
    
    func getAll(for userId: String) async throws -> [T]
    func getById(_ id: String) async throws -> T?
    func create(_ item: T) async throws
    func update(_ item: T) async throws
    func delete(_ id: String) async throws
}

/// Repository for inbox items with additional filtering.
public protocol InboxRepositoryProtocol: Repository where T == InboxItem {
    func getUnprocessed(for userId: String) async throws -> [InboxItem]
    func getByStatus(_ status: InboxItemStatus, for userId: String) async throws -> [InboxItem]
}

/// Repository for tasks with filtering and sorting.
public protocol TaskRepositoryProtocol: Repository where T == LifeTask {
    func getActive(for userId: String) async throws -> [LifeTask]
    func getByLifeArea(_ area: LifeArea, for userId: String) async throws -> [LifeTask]
    func getByEnergyLevel(_ energy: EnergyLevel, for userId: String) async throws -> [LifeTask]
    func getOverdue(for userId: String) async throws -> [LifeTask]
    func getCompletedToday(for userId: String) async throws -> [LifeTask]
}

/// Repository for health summaries.
public protocol HealthSummaryRepositoryProtocol: Repository where T == HealthSummary {
    func getForDate(_ date: Date, userId: String) async throws -> HealthSummary?
    func getForDateRange(from: Date, to: Date, userId: String) async throws -> [HealthSummary]
    func getLatest(for userId: String) async throws -> HealthSummary?
}

/// Repository for productivity sessions.
public protocol ProductivityRepositoryProtocol: Repository where T == ProductivitySession {
    func getForDate(_ date: Date, userId: String) async throws -> [ProductivitySession]
    func getTotalFocusMinutes(for date: Date, userId: String) async throws -> Int
}

/// Repository for memory entries with semantic search.
public protocol MemoryRepositoryProtocol: Repository where T == MemoryEntry {
    func search(query: String, userId: String, limit: Int) async throws -> [MemoryEntry]
    func getByLifeArea(_ area: LifeArea, userId: String) async throws -> [MemoryEntry]
}

// MARK: - Health Data Provider

/// Protocol for accessing health data (HealthKit on iOS, manual input fallback).
public protocol HealthDataProvider: Sendable {
    func requestAuthorization() async throws -> Bool
    func fetchTodaysSummary() async throws -> HealthSummary
    func fetchSleepData(for date: Date) async throws -> HealthSummary
    func fetchHeartRateData(for date: Date) async throws -> HealthSummary
    func fetchWorkoutData(for date: Date) async throws -> HealthSummary
    var isAvailable: Bool { get }
}
