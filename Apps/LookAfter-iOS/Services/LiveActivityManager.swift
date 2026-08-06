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
        isPaused: Bool
    ) {
        isExecutionDriven = false
        // Performance: defer ActivityKit until after focus UI paints.
        // Activity.request is MainActor and can block for hundreds of ms on device.
        Task { @MainActor in
            // Let FocusSessionView layout/paint first.
            await Task.yield()
            await Task.yield()
            // Brief pause so the first frame is committed before ActivityKit work.
            try? await Task.sleep(nanoseconds: 250_000_000)

            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

            if let existing = focusActivity {
                focusActivity = nil
                Task {
                    await existing.end(nil, dismissalPolicy: .immediate)
                }
            }

            let attributes = FocusActivityAttributes(
                taskTitle: taskTitle,
                sessionNumber: sessionNumber,
                categoryIcon: "brain.head.profile"
            )
            let state = FocusActivityAttributes.ContentState(
                taskTitle: taskTitle,
                sessionEndDate: sessionEndDate,
                isPaused: isPaused,
                isOnBreak: isOnBreak,
                sessionLabel: sessionLabel,
                remainingLabel: remainingLabel,
                constraintType: "Flexible",
                progressFraction: 0,
                nextUpSummary: "",
                categoryRaw: FocusTaskCategory.deepWork.rawValue,
                surfaceModeRaw: ExecutionSurfaceMode.flexible.rawValue,
                showsStrictCountdown: true
            )

            do {
                focusActivity = try Activity.request(
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
        isPaused: Bool
    ) {
        // Manual focus takes ownership over schedule-driven projection.
        isExecutionDriven = false
        if focusActivity == nil {
            startFocusActivity(
                taskTitle: taskTitle,
                sessionNumber: sessionNumber,
                sessionEndDate: sessionEndDate,
                isOnBreak: isOnBreak,
                sessionLabel: sessionLabel,
                remainingLabel: remainingLabel,
                isPaused: isPaused
            )
            return
        }

        guard let focusActivity else { return }
        let state = FocusActivityAttributes.ContentState(
            taskTitle: taskTitle,
            sessionEndDate: sessionEndDate,
            isPaused: isPaused,
            isOnBreak: isOnBreak,
            sessionLabel: sessionLabel,
            remainingLabel: remainingLabel,
            constraintType: isOnBreak ? "Recovery" : "Flexible",
            progressFraction: 0,
            nextUpSummary: "",
            categoryRaw: FocusTaskCategory.deepWork.rawValue,
            surfaceModeRaw: isOnBreak
                ? ExecutionSurfaceMode.recovery.rawValue
                : ExecutionSurfaceMode.flexible.rawValue,
            showsStrictCountdown: !isPaused
        )
        Task {
            await focusActivity.update(.init(state: state, staleDate: sessionEndDate))
        }
    }

    func endFocusActivity() {
        guard let focusActivity else { return }
        Task {
            await focusActivity.end(nil, dismissalPolicy: .immediate)
        }
        self.focusActivity = nil
        isExecutionDriven = false
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

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = Self.contentState(from: snapshot)
        let icon = snapshot.category.systemImage

        if let focusActivity, isExecutionDriven {
            Task {
                await focusActivity.update(.init(state: state, staleDate: snapshot.windowEnd))
            }
            return
        }

        // Replace any stale activity.
        if let existing = focusActivity {
            focusActivity = nil
            Task { await existing.end(nil, dismissalPolicy: .immediate) }
        }

        let attributes = FocusActivityAttributes(
            taskTitle: snapshot.taskTitle,
            sessionNumber: 1,
            categoryIcon: icon
        )
        do {
            focusActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: snapshot.windowEnd),
                pushType: nil
            )
            isExecutionDriven = true
        } catch {
            print("Execution Live Activity failed: \(error.localizedDescription)")
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
        
        endNowPin()
        
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
        guard let nowPinActivity else { return }
        Task {
            await nowPinActivity.end(nil, dismissalPolicy: .immediate)
        }
        self.nowPinActivity = nil
    }

    /// Ends every live activity after factory reset.
    func endAllActivities() {
        endFocusActivity()
        endNowPin()
    }
}
