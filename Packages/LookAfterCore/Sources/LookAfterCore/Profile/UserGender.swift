import Foundation

public enum UserGender: String, Codable, Sendable, CaseIterable, Identifiable {
    case female
    case male
    case nonBinary
    case preferNotToSay

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .female: return "Female"
        case .male: return "Male"
        case .nonBinary: return "Non-binary"
        case .preferNotToSay: return "Prefer not to say"
        }
    }
}
