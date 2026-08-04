import Foundation

/// A single, independently testable scheduling rule.
public protocol FlowSchedulingRuleProtocol: Sendable {
    /// Stable identifier for logging, tests, and the rule matrix.
    var identifier: String { get }
    /// Evaluates and mutates scheduling state. Must be deterministic for identical inputs.
    func apply(to state: inout MutableSchedulingState, context: FlowSchedulingContext)
}

/// Type-erased wrapper so the engine can store heterogeneous rules in a homogeneous array.
public struct AnyFlowSchedulingRule: FlowSchedulingRuleProtocol, Sendable {
    public let identifier: String
    private let applyImpl: @Sendable (inout MutableSchedulingState, FlowSchedulingContext) -> Void

    public init<R: FlowSchedulingRuleProtocol>(_ rule: R) {
        identifier = rule.identifier
        applyImpl = { state, context in
            rule.apply(to: &state, context: context)
        }
    }

    public func apply(to state: inout MutableSchedulingState, context: FlowSchedulingContext) {
        applyImpl(&state, context)
    }
}
