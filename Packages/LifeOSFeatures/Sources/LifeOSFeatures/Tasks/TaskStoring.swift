import Foundation
import LifeOSCore
import LifeOSData

@MainActor
protocol TaskStoring {
    func localSnapshot(for userId: String) -> TaskListSnapshot
    func getTaskLists(for userId: String) async throws -> TaskListSnapshot
    func getActive(for userId: String) async throws -> [LifeTask]
    func getCompletedToday(for userId: String) async throws -> [LifeTask]
    func getAll(for userId: String) async throws -> [LifeTask]
    func create(_ task: LifeTask) async throws
    func update(_ task: LifeTask) async throws
    func delete(_ id: String) async throws
}

extension TaskRepository: TaskStoring {}
