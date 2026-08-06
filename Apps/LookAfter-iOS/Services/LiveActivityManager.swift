import Foundation
import ActivityKit
import LookAfterCore

/// Manages pinned Live Activities on Lock Screen and Dynamic Island.
@MainActor
final class LiveActivityManager {

    static let shared = LiveActivityManager()

    private var focusActivity: Activity<FocusActivityAttributes>?
    private var nowPinActivity: Activity<NowPinActivityAttributes>?
    /// When true, schedule-driven execution owns the focus activity slot.
    private(set) var isExecutionDriven = false

    /// Serializes start/update/end so async `Activity.end` cannot race a new `Activity.request`.
    private var focusOperationChain: Task<Void, Never>?
    private var nowPinEndTask: Task<Void, Never>?

    private init() {}

    var isNowPinned: Bool {
        nowPinActivity != nil
    }

    var hasFocusActivity: Bool {
        focusActivity != nil
    }

    // MARK: - Focus Session (manual ADHD / pomodoro)

    func startFocusActivity(
        taskTitle: String,
        sessionNumber: Int,
        sessionEndDate: Date,
        isOnBreak: Bool,
        sessionLabel: String,
        remainingLabel: String,
        isPaused: Bool,
        progressFraction: Double
    ) {
        isExecutionDriven = false
        enqueueFocusOperation(deferStartup: true) { [weak self] in
            guard let self else { return }
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

            await self.endFocusActivityIfNeeded()

            let attributes = FocusActivityAttributes(
                taskTitle: taskTitle,
                sessionNumber: sessionNumber,
                categoryIcon: "brain.head.profile"
            )
            let state = Self.manualContentState(
                taskTitle: taskTitle,
                sessionEndDate: sessionEndDate,
                isOnBreak: isOnBreak,
                sessionLabel: sessionLabel,
                remainingLabel: remainingLabel,
                isPaused: isPaused,
                progressFraction: progressFraction
            )

            do {
                self.focusActivity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: sessionEndDate),
                    pushType: nil
                )
            } catch {
                print("Focus Live Activity failed: \(error.localizedDescription)")
            }
        }
    }

    func updateFocusActivity(
        taskTitle: String,
        sessionNumber: Int,
        sessionEndDate: Date,
        isOnBreak: Bool,
        sessionLabel: String,
        remainingLabel: String,
        isPaused: Bool,
        progressFraction: Double
    ) {
        isExecutionDriven = false
        if focusActivity == nil {
            startFocusActivity(
                taskTitle: taskTitle,
                sessionNumber: sessionNumber,
                sessionEndDate: sessionEndDate,
                isOnBreak: isOnBreak,
                sessionLabel: sessionLabel,
                remainingLabel: remainingLabel,
                isPaused: isPaused,
                progressFraction: progressFraction
            )
            return
        }

        enqueueFocusOperation(deferStartup: false) { [weak self] in
            guard let self, let focusActivity = self.focusActivity else { return }
            let state = Self.manualContentState(
                taskTitle: taskTitle,
                sessionEndDate: sessionEndDate,
                isOnBreak: isOnBreak,
                sessionLabel: sessionLabel,
                remainingLabel: remainingLabel,
                isPaused: isPaused,
                progressFraction: progressFraction
            )
            await focusActivity.update(.init(state: state, staleDate: sessionEndDate))
        }
    }

    func endFocusActivity() {
        enqueueFocusOperation(deferStartup: false) { [weak self] in
            await self?.endFocusActivityIfNeeded()
        }
    }

    func endFocusActivityAndWait() async {
        endFocusActivity()
        await focusOperationChain?.value
    }

    // MARK: - Execution Layer (schedule-driven)

    /// Starts or updates a Live Activity from an `ExecutionBlockSnapshot`.
    /// Skipped while a manual ADHD focus session owns the slot.
    func applyExecutionBlock(_ snapshot: ExecutionBlockSnapshot, manualFocusActive: Bool) {
        guard !manualFocusActive else { return }
        guard !UITestLaunchConfiguration.shouldSkipLiveActivity else { return }

        guard snapshot.surfaceMode.projectsLiveActivity,
              ExecutionBlockResolver.shouldProjectEnvironment(for: snapshot) else {
            if isExecutionDriven {
                endFocusActivity()
            }
            return
        }

        let state = Self.contentState(from: snapshot)
        let icon = snapshot.category.systemImage
        let staleDate = snapshot.windowEnd

        if let focusActivity, isExecutionDriven {
            enqueueFocusOperation(deferStartup: false) { [weak self] in
                guard let self, let current = self.focusActivity, current.id == focusActivity.id else { return }
                await current.update(.init(state: state, staleDate: staleDate))
            }
            return
        }

        enqueueFocusOperation(deferStartup: true) { [weak self] in
            guard let self else { return }
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

            await self.endFocusActivityIfNeeded()

            let attributes = FocusActivityAttributes(
                taskTitle: snapshot.taskTitle,
                sessionNumber: 1,
                categoryIcon: icon
            )
            do {
                self.focusActivity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: staleDate),
                    pushType: nil
                )
                self.isExecutionDriven = true
            } catch {
                print("Execution Live Activity failed: \(error.localizedDescription)")
            }
        }
    }

    static func contentState(from snapshot: ExecutionBlockSnapshot) -> FocusActivityAttributes.ContentState {
        let remaining = max(0, Int(snapshot.remainingSeconds / 60))
        let remainingLabel: String
        switch snapshot.surfaceMode {
        case .recovery:
            remainingLabel = "Recovery"
        case .fluidGap:
            remainingLabel = remaining > 0 ? "\(remaining)m" : "Gap"
        case .idle:
            remainingLabel = ""
        case .anchored, .flexible:
            remainingLabel = remaining > 0 ? "\(remaining)m" : "<1m"
        }

        return FocusActivityAttributes.ContentState(
            taskTitle: snapshot.taskTitle,
            sessionEndDate: snapshot.windowEnd,
            isPaused: false,
            isOnBreak: snapshot.surfaceMode == .recovery,
            sessionLabel: snapshot.category.displayName,
            remainingLabel: remainingLabel,
            constraintType: snapshot.constraintLabel,
            progressFraction: snapshot.progressFraction,
            nextUpSummary: snapshot.nextUpSummary,
            categoryRaw: snapshot.category.rawValue,
            surfaceModeRaw: snapshot.surfaceMode.rawValue,
            showsStrictCountdown: snapshot.surfaceMode.showsStrictCountdown
        )
    }

    // MARK: - Pinned Now

    func startNowPin(from snapshot: WidgetSnapshot) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard let title = snapshot.topTaskTitle, !title.isEmpty else { return }

        Task { @MainActor in
            await endNowPinIfNeeded()

            let attributes = NowPinActivityAttributes(pinnedAt: Date())
            let state = NowPinActivityAttributes.ContentState(
                topTaskTitle: title,
                energyScore: snapshot.energyScore,
                energyLevel: snapshot.energyLevel,
                recommendation: snapshot.recommendation,
                estimatedMinutes: snapshot.topTaskMinutes ?? 25
            )

            do {
                nowPinActivity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: nil),
                    pushType: nil
                )
            } catch {
                print("Now pin Live Activity failed: \(error.localizedDescription)")
            }
        }
    }

    func updateNowPin(from snapshot: WidgetSnapshot) {
        guard let nowPinActivity else { return }
        guard let title = snapshot.topTaskTitle, !title.isEmpty else { return }

        let state = NowPinActivityAttributes.ContentState(
            topTaskTitle: title,
            energyScore: snapshot.energyScore,
            energyLevel: snapshot.energyLevel,
            recommendation: snapshot.recommendation,
            estimatedMinutes: snapshot.topTaskMinutes ?? 25
        )
        Task {
            await nowPinActivity.update(.init(state: state, staleDate: nil))
        }
    }

    func endNowPin() {
        Task { @MainActor in
            await endNowPinIfNeeded()
        }
    }

    /// Ends every live activity after factory reset.
    func endAllActivities() {
        endFocusActivity()
        endNowPin()
    }

    // MARK: - Private

    private static func manualContentState(
        taskTitle: String,
        sessionEndDate: Date,
        isOnBreak: Bool,
        sessionLabel: String,
        remainingLabel: String,
        isPaused: Bool,
        progressFraction: Double
    ) -> FocusActivityAttributes.ContentState {
        FocusActivityAttributes.ContentState(
            taskTitle: taskTitle,
            sessionEndDate: sessionEndDate,
            isPaused: isPaused,
            isOnBreak: isOnBreak,
            sessionLabel: sessionLabel,
            remainingLabel: remainingLabel,
            constraintType: isOnBreak ? "Recovery" : "Flexible",
            progressFraction: progressFraction,
            nextUpSummary: "",
            categoryRaw: FocusTaskCategory.deepWork.rawValue,
            surfaceModeRaw: isOnBreak
                ? ExecutionSurfaceMode.recovery.rawValue
                : ExecutionSurfaceMode.flexible.rawValue,
            showsStrictCountdown: !isPaused
        )
    }

    private func enqueueFocusOperation(
        deferStartup: Bool,
        _ operation: @escaping @MainActor () async -> Void
    ) {
        let previous = focusOperationChain
        focusOperationChain = Task { @MainActor in
            if let previous { await previous.value }
            if deferStartup {
                await Task.yield()
                await Task.yield()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            await operation()
        }
    }

    private func endFocusActivityIfNeeded() async {
        guard let activity = focusActivity else { return }
        focusActivity = nil
        isExecutionDriven = false
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    private func endNowPinIfNeeded() async {
        if let endTask = nowPinEndTask {
            await endTask.value
            nowPinEndTask = nil
        }
        guard let activity = nowPinActivity else { return }
        nowPinActivity = nil
        await activity.end(nil, dismissalPolicy: .immediate)
    }
}
