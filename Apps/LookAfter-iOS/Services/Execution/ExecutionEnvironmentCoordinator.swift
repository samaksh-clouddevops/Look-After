import Foundation
import Combine
import LookAfterCore

/// Top-level Execution Layer coordinator.
///
/// Observes schedule state (tasks) + wall clock, resolves the active block via
/// `ExecutionBlockResolver`, and fans out to Focus Filters + Live Activities.
///
/// Unidirectional: all surface updates originate from resolved snapshots only.
@MainActor
final class ExecutionEnvironmentCoordinator: ObservableObject {

    static let shared = ExecutionEnvironmentCoordinator()

    @Published private(set) var activeSnapshot: ExecutionBlockSnapshot = .idle
    @Published private(set) var isRunning = false

    private var tasks: [LifeTask] = []
    private var manualFocusActive = false
    private var tickTask: Task<Void, Never>?
    private var lastResolutionIdentity: String?
    private var lastPinProgressBucket: Int = -1

    /// Seconds between re-evaluations when a block is active.
    private let activeTickInterval: TimeInterval = 30
    /// Coarser poll when idle / waiting for the next block.
    private let idleTickInterval: TimeInterval = 60

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        scheduleNextTick(immediate: true)
    }

    func stop() {
        isRunning = false
        tickTask?.cancel()
        tickTask = nil
        Task {
            await ExecutionFocusCoordinator.shared.clear()
            ActivityStateController.shared.end()
        }
        activeSnapshot = .idle
        lastResolutionIdentity = nil
    }

    /// Push latest tasks from the SSOT (TaskStore / TasksViewModel).
    func updateTasks(_ tasks: [LifeTask]) {
        self.tasks = tasks
        if isRunning {
            resolveAndProject(now: Date(), forceLiveActivity: false)
        }
    }

    /// Manual ADHD focus session preempts schedule-driven projection.
    func setManualFocusActive(_ active: Bool) {
        manualFocusActive = active
        if active {
            // Manual path owns Live Activity via WidgetSyncService.
            lastResolutionIdentity = nil
        } else if isRunning {
            resolveAndProject(now: Date(), forceLiveActivity: false)
        }
    }

    /// Force an immediate resolve (scene become-active, task list change).
    func refresh(now: Date = Date(), forceLiveActivity: Bool = false) {
        guard isRunning else { return }
        resolveAndProject(now: now, forceLiveActivity: forceLiveActivity)
    }

    /// Push a final Live Activity update before the app suspends.
    func prepareForBackground(now: Date = Date()) {
        guard isRunning else { return }
        resolveAndProject(now: now, forceLiveActivity: true)
    }

    /// Called when the pinned NOW Live Activity should reflect the latest schedule.
    var onPinRefreshNeeded: (() -> Void)?

    // MARK: - Resolve

    private func resolveAndProject(now: Date, forceLiveActivity: Bool = false) {
        let snapshot = ExecutionBlockResolver.resolve(tasks: tasks, now: now)
        activeSnapshot = snapshot

        let identity = "\(snapshot.id)|\(snapshot.surfaceMode.rawValue)|\(snapshot.taskID ?? "")"
        let identityChanged = identity != lastResolutionIdentity
        lastResolutionIdentity = identity
        let progressBucket = Int((snapshot.progressFraction * 100).rounded(.down))
        let progressChanged = progressBucket != lastPinProgressBucket
        lastPinProgressBucket = progressBucket

        ActivityStateController.shared.apply(
            snapshot: snapshot,
            manualFocusActive: manualFocusActive,
            force: forceLiveActivity
        )

        if identityChanged || forceLiveActivity {
            Task {
                await ExecutionFocusCoordinator.shared.apply(snapshot: snapshot)
            }
        }

        if WidgetSyncService.shared.isNowPinned,
           identityChanged || progressChanged || forceLiveActivity {
            onPinRefreshNeeded?()
        }
    }

    // MARK: - Ticking

    private func scheduleNextTick(immediate: Bool) {
        tickTask?.cancel()
        tickTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if !immediate {
                let interval = self.activeSnapshot.surfaceMode == .idle
                    ? self.idleTickInterval
                    : self.activeTickInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
            guard !Task.isCancelled, self.isRunning else { return }
            self.resolveAndProject(now: Date(), forceLiveActivity: false)
            // Align next tick to upcoming block boundary when useful.
            if let delay = self.secondsUntilBoundary(from: Date()), delay > 0, delay < self.activeTickInterval {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled, self.isRunning else { return }
                self.resolveAndProject(now: Date(), forceLiveActivity: false)
            }
            self.scheduleNextTick(immediate: false)
        }
    }

    private func secondsUntilBoundary(from now: Date) -> TimeInterval? {
        let end = activeSnapshot.windowEnd
        guard end > now, activeSnapshot.surfaceMode != .idle else { return nil }
        return end.timeIntervalSince(now) + 0.5
    }
}
