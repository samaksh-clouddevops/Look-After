import Foundation
import Combine

/// Coalesces rapid updates into a single `@Published` emission after a short delay.
/// Use this to avoid thrashing SwiftUI when multiple sources publish in the same run loop.
@MainActor
public final class StateCoalescer<Value>: ObservableObject {
    @Published public private(set) var value: Value

    private var pendingValue: Value?
    private var coalesceTask: Task<Void, Never>?
    private let delayNanoseconds: UInt64

    /// - Parameters:
    ///   - initialValue: Starting value
    ///   - delayMilliseconds: How long to wait before publishing (default ~1 frame at 60fps)
    public init(initialValue: Value, delayMilliseconds: UInt64 = 16) {
        self.value = initialValue
        self.delayNanoseconds = delayMilliseconds * 1_000_000
    }

    /// Schedule an update. Multiple calls within the delay window collapse to the latest value.
    public func update(_ newValue: Value) {
        pendingValue = newValue
        coalesceTask?.cancel()
        coalesceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.delayNanoseconds ?? 16_000_000)
            guard let self, !Task.isCancelled, let pending = self.pendingValue else { return }
            self.value = pending
            self.pendingValue = nil
        }
    }

    /// Publish immediately without waiting for the coalesce window.
    public func flush(_ newValue: Value) {
        coalesceTask?.cancel()
        coalesceTask = nil
        pendingValue = nil
        value = newValue
    }

    deinit {
        coalesceTask?.cancel()
    }
}
