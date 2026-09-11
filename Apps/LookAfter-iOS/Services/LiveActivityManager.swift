import Foundation
@preconcurrency import ActivityKit
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
    private var nowPinOperationChain: Task<Void, Never>?
    private var nowPinEndTask: Task<Void, Never>?

    private init() {}

    var isNowPinned: Bool {
        reattachNowPinIfNeeded()
        return nowPinActivity != nil
    }

    var hasFocusActivity: Bool {
        focusActivity != nil
    }

    /// Reconnect to an existing system Live Activity after relaunch or if the local ref was lost.
    func reattachNowPinIfNeeded() {
        guard nowPinActivity == nil else { return }
        nowPinActivity = Activity<NowPinActivityAttributes>.activities.first
        if let nowPinActivity {
            PinNowLogger.info("Reattached Now Pin activity id=\(nowPinActivity.id)")
        }
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
        enqueueFocusOperation(deferStartup: false) { [weak self] in
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
                    content: .init(state: state, staleDate: Self.staleDate(for: sessionEndDate)),
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
            await focusActivity.update(.init(state: state, staleDate: Self.staleDate(for: sessionEndDate)))
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
        guard !WidgetSyncService.shared.isNowPinned, !isNowPinned else { return }
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

        if let focusActivity, isExecutionDriven {
            enqueueFocusOperation(deferStartup: false) { [weak self] in
                guard let self, let current = self.focusActivity, current.id == focusActivity.id else { return }
                await current.update(.init(state: state, staleDate: Self.staleDate(for: snapshot.windowEnd)))
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
                    content: .init(state: state, staleDate: Self.staleDate(for: snapshot.windowEnd)),
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

    @discardableResult
    func refreshNowPin(from snapshot: WidgetSnapshot) async -> PinNowResult {
        await enqueueNowPinOperationReturning {
            self.reattachNowPinIfNeeded()
            if self.nowPinActivity != nil {
                return await self.performUpdateNowPin(from: snapshot)
            }
            return await self.performStartNowPin(from: snapshot)
        }
    }

    @discardableResult
    func startNowPin(from snapshot: WidgetSnapshot) async -> PinNowResult {
        await enqueueNowPinOperationReturning {
            await self.performStartNowPin(from: snapshot)
        }
    }

    @discardableResult
    func updateNowPin(from snapshot: WidgetSnapshot) async -> PinNowResult {
        await enqueueNowPinOperationReturning {
            self.reattachNowPinIfNeeded()
            if self.nowPinActivity != nil {
                return await self.performUpdateNowPin(from: snapshot)
            }
            return await self.performStartNowPin(from: snapshot)
        }
    }

    func endNowPin() {
        Task { @MainActor in
            await endNowPinAndWait()
        }
    }

    func endNowPinAndWait() async {
        await enqueueNowPinOperationReturning {
            await self.endNowPinIfNeeded()
            return PinNowResult.ok("Unpinned")
        }
    }

    /// Ends every live activity after factory reset.
    func endAllActivities() {
        endFocusActivity()
        endNowPin()
    }

    // MARK: - Private

    @discardableResult
    private func enqueueNowPinOperationReturning(
        _ operation: @escaping @MainActor () async -> PinNowResult
    ) async -> PinNowResult {
        let previous = nowPinOperationChain
        let task = Task { @MainActor () async -> PinNowResult in
            if let previous { await previous.value }
            return await operation()
        }
        nowPinOperationChain = Task { _ = await task.value }
        return await task.value
    }

    @discardableResult
    private func performStartNowPin(from snapshot: WidgetSnapshot) async -> PinNowResult {
        guard !UITestLaunchConfiguration.shouldSkipLiveActivity else {
            return PinNowResult.failed("Live Activities disabled in UI tests.")
        }

        let auth = ActivityAuthorizationInfo()
        guard auth.areActivitiesEnabled else {
            PinNowLogger.error("Live Activities disabled in Settings → \(UserFacingCopy.productName) → Live Activities")
            return PinNowResult.failed(
                "Live Activities are off. Enable them in Settings → \(UserFacingCopy.productName) → Live Activities."
            )
        }

        guard let title = snapshot.resolvedTopTaskTitle else {
            PinNowLogger.error("Missing top task title in widget snapshot")
            return PinNowResult.failed("No next step to pin.")
        }

        await focusOperationChain?.value
        await endFocusActivityIfNeeded()
        await endNowPinIfNeeded()

        let attributes = NowPinActivityAttributes(
            pinnedAt: Date(),
            categoryIcon: snapshot.pinCategoryIcon
        )
        let state = Self.nowPinContentState(from: snapshot, title: title)

        PinNowLogger.info("Requesting Now Pin Live Activity for \"\(title)\"")

        do {
            nowPinActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: Self.staleDate(for: snapshot.pinWindowEnd)),
                pushType: nil
            )
            PinNowLogger.info("Live Activity started id=\(nowPinActivity?.id ?? "nil")")
            return PinNowResult.ok("Pinned \"\(title)\" to Lock Screen")
        } catch {
            nowPinActivity = nil
            PinNowLogger.error("Activity.request failed: \(error.localizedDescription)")
            return PinNowResult.failed("Could not pin: \(error.localizedDescription)")
        }
    }

    @discardableResult
    private func performUpdateNowPin(from snapshot: WidgetSnapshot) async -> PinNowResult {
        reattachNowPinIfNeeded()
        guard let nowPinActivity else {
            return await performStartNowPin(from: snapshot)
        }
        guard let title = snapshot.resolvedTopTaskTitle else {
            return PinNowResult.failed("No next step to update.")
        }

        let state = Self.nowPinContentState(from: snapshot, title: title)
        await nowPinActivity.update(ActivityContent(state: state, staleDate: Self.staleDate(for: snapshot.pinWindowEnd)))
        PinNowLogger.info("Updated Now Pin Live Activity for \"\(title)\"")
        return PinNowResult.ok("Updated pinned task")
    }

    /// Marks the activity stale shortly after the intended window so Lock Screen doesn't keep a dead timer.
    private static func staleDate(for end: Date?, fallbackMinutes: TimeInterval = 30 * 60) -> Date {
        let candidate = end ?? Date().addingTimeInterval(fallbackMinutes)
        return max(candidate, Date().addingTimeInterval(60))
    }

    private static func nowPinContentState(from snapshot: WidgetSnapshot, title: String) -> NowPinActivityAttributes.ContentState {
        let contextLine = snapshot.pinContextLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? snapshot.recommendation
            : snapshot.pinContextLine
        return NowPinActivityAttributes.ContentState(
            topTaskTitle: title,
            energyScore: snapshot.energyScore,
            energyLevel: snapshot.energyLevel,
            contextLine: contextLine,
            estimatedMinutes: snapshot.topTaskMinutes ?? 25,
            scheduleLabel: snapshot.pinScheduleLabel,
            constraintLabel: snapshot.pinConstraintLabel,
            nextUpSummary: snapshot.pinNextUpSummary,
            progressFraction: snapshot.pinProgressFraction,
            sectionLabel: snapshot.pinSectionLabel,
            categoryIcon: snapshot.pinCategoryIcon,
            windowStart: snapshot.pinWindowStart,
            windowEnd: snapshot.pinWindowEnd
        )
    }

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
        reattachNowPinIfNeeded()
        guard let activity = nowPinActivity else { return }
        nowPinActivity = nil
        await activity.end(nil, dismissalPolicy: .immediate)
    }
}
