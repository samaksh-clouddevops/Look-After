import Foundation
import Combine
import LifeOSCore

@MainActor
public final class HomeManagementViewModel: ObservableObject {
    @Published public var maintenanceTasks: [HomeMaintenanceTask] = []
    @Published public var inventoryItems: [HomeInventoryItem] = []
    
    // Search queries
    @Published public var inventorySearchQuery: String = ""
    
    public init() {
        loadMockData()
    }
    
    public var filteredInventory: [HomeInventoryItem] {
        guard !inventorySearchQuery.isEmpty else { return inventoryItems }
        let lowercasedQuery = inventorySearchQuery.lowercased()
        return inventoryItems.filter {
            $0.name.lowercased().contains(lowercasedQuery) ||
            $0.location.lowercased().contains(lowercasedQuery) ||
            $0.tags.contains(where: { $0.lowercased().contains(lowercasedQuery) })
        }
    }
    
    public var urgentMaintenanceTasks: [HomeMaintenanceTask] {
        maintenanceTasks.filter { $0.isOverdue || Calendar.current.isDate($0.nextDue, inSameDayAs: Date()) }
    }
    
    public var upcomingMaintenanceTasks: [HomeMaintenanceTask] {
        maintenanceTasks.filter { !$0.isOverdue && !Calendar.current.isDate($0.nextDue, inSameDayAs: Date()) }
    }
    
    public func toggleTaskCompletion(_ task: HomeMaintenanceTask) {
        if let index = maintenanceTasks.firstIndex(where: { $0.id == task.id }) {
            var updatedTask = maintenanceTasks[index]
            updatedTask.lastCompleted = Date()
            updatedTask.nextDue = Calendar.current.date(byAdding: .day, value: updatedTask.intervalDays, to: Date()) ?? Date()
            maintenanceTasks[index] = updatedTask
        }
    }
    
    private func loadMockData() {
        maintenanceTasks = [
            HomeMaintenanceTask(title: "Change HVAC Filter", intervalDays: 90, nextDue: Calendar.current.date(byAdding: .day, value: -2, to: Date())!, assignedTo: "User"),
            HomeMaintenanceTask(title: "Deep Clean Kitchen", intervalDays: 30, nextDue: Date(), assignedTo: "Partner", isShared: true),
            HomeMaintenanceTask(title: "Run Dishwasher Self-Clean", intervalDays: 30, nextDue: Calendar.current.date(byAdding: .day, value: 5, to: Date())!),
            HomeMaintenanceTask(title: "Water Indoor Plants", intervalDays: 7, nextDue: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
        ]
        
        inventoryItems = [
            HomeInventoryItem(name: "AA Batteries", location: "Utility Drawer, Kitchen", quantity: 8, tags: ["electronics", "utilities"]),
            HomeInventoryItem(name: "Trash Bags (13 Gal)", location: "Under Kitchen Sink", quantity: 45, tags: ["cleaning", "kitchen"]),
            HomeInventoryItem(name: "Passport", location: "Filing Cabinet, Master Bedroom", quantity: 1, tags: ["documents", "travel"]),
            HomeInventoryItem(name: "Air Filter (20x20x1)", location: "Garage Shelf C", quantity: 2, tags: ["maintenance", "HVAC"]),
            HomeInventoryItem(name: "Tylenol", location: "Master Bathroom Medicine Cabinet", quantity: 1, tags: ["health", "medication"])
        ]
    }
}
