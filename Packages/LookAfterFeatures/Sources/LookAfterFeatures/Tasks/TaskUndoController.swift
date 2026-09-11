import Foundation
import LookAfterCore

/// Undo toast auto-dismiss timer for `TasksViewModel` (Q3 collaborator).
@MainActor
public final class TaskUndoController {
    private weak var viewModel: TasksViewModel?
    private var undoDismissTask: Task<Void, Never>?

    public init() {}

    public func attach(viewModel: TasksViewModel) {
        self.viewModel = viewModel
    }

    public func scheduleAutoExpire(for actionID: String) {
        undoDismissTask?.cancel()
        undoDismissTask = Task { [weak viewModel] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                viewModel?.expireUndoIfMatching(actionID)
            }
        }
    }

    public func cancelAutoExpire() {
        undoDismissTask?.cancel()
        undoDismissTask = nil
    }
}
