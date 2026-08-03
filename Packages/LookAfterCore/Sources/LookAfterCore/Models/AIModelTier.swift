import Foundation

/// Selects which GLM model tier handles a request.
public enum AIModelTier: String, Codable, Sendable, CaseIterable {
    /// Coach, executive planning, day replan — highest quality.
    case premium
    /// Life model compile, daily scheduling, inbox — balanced cost and reasoning.
    case standard
    /// Task semantics, decomposition, auto-fill — fast structured JSON.
    case economy

    public var displayLabel: String {
        switch self {
        case .premium: return "Premium"
        case .standard: return "Standard"
        case .economy: return "Economy"
        }
    }
}
