import Foundation
import LookAfterCore

/// Bridges `ExecutionBlockSnapshot` to in-app Focus Filter context.
///
/// Apps cannot programmatically force-enable system Focus Modes. The model is:
/// 1. `LookAfterFocusIntent` (SetFocusFilterIntent) exposes task-category parameters.
/// 2. User binds that filter to Work / Mindfulness / etc. once in Settings → Focus.
/// 3. When schedule enters an anchored / high-confidence flexible block, we publish the
///    active task context so notification policy can suppress low-priority noise and
///    the filter representation stays ready if the bound Focus is active.
@MainActor
final class ExecutionFocusCoordinator {

    static let shared = ExecutionFocusCoordinator()

    static let didChangeNotification = Notification.Name("LookAfter.ExecutionFocusDidChange")

    private var lastAppliedKey: String?
    private var isFilterActive = false

    private init() {}

    /// Evaluate snapshot and publish / clear Focus Filter context.
    func apply(snapshot: ExecutionBlockSnapshot) async {
        let shouldFilter = shouldRequestFocusFilter(for: snapshot)

        if !shouldFilter {
            clearFilterIfNeeded()
            return
        }

        let key = filterKey(for: snapshot)
        guard key != lastAppliedKey else { return }

        await publishFocusContext(
            category: snapshot.category,
            taskTitle: snapshot.taskTitle,
            suppressLowPriority: snapshot.category.suppressesLowPriorityNotifications,
            constraintLabel: snapshot.constraintLabel
        )
        lastAppliedKey = key
        isFilterActive = true
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: snapshot.category.rawValue
        )
    }

    func clear() async {
        clearFilterIfNeeded()
    }

    // MARK: - Private

    private func shouldRequestFocusFilter(for snapshot: ExecutionBlockSnapshot) -> Bool {
        guard ExecutionBlockResolver.shouldProjectEnvironment(for: snapshot) else { return false }
        guard snapshot.category.requestsFocusFilter else { return false }
        switch snapshot.surfaceMode {
        case .anchored, .flexible:
            return true
        case .recovery, .fluidGap, .idle:
            return false
        }
    }

    private func filterKey(for snapshot: ExecutionBlockSnapshot) -> String {
        "\(snapshot.taskID ?? snapshot.id)|\(snapshot.category.rawValue)|\(snapshot.surfaceMode.rawValue)"
    }

    private func publishFocusContext(
        category: FocusTaskCategory,
        taskTitle: String,
        suppressLowPriority: Bool,
        constraintLabel: String
    ) async {
        if #available(iOS 17.0, *) {
            let intent = LookAfterFocusIntent(
                category: category,
                taskTitle: taskTitle,
                suppressLowPriority: suppressLowPriority,
                constraintLabel: constraintLabel
            )
            _ = try? await intent.perform()
        } else {
            ExecutionFocusFilterStore.shared.record(
                category: category,
                taskTitle: taskTitle,
                suppressLowPriority: suppressLowPriority
            )
        }
    }

    private func clearFilterIfNeeded() {
        guard isFilterActive || lastAppliedKey != nil else { return }
        lastAppliedKey = nil
        isFilterActive = false
        ExecutionFocusFilterStore.shared.clear()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
