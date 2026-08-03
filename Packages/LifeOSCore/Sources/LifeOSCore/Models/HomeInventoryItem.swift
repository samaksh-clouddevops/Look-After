import Foundation

/// Represents a physical item in the home's Digital Twin.
public struct HomeInventoryItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var location: String
    public var quantity: Int
    public var tags: [String]
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        location: String,
        quantity: Int = 1,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.quantity = quantity
        self.tags = tags
    }
}
