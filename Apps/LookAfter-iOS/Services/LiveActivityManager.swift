import Foundation
import ActivityKit
import LookAfterCore

/// Manages pinned Live Activities on Lock Screen and Dynamic Island.
@MainActor
final class LiveActivityManager {
    
    static let shared = LiveActivityManager()
    
    private var focusActivity: Activity<FocusActivityAttributes>?
    private var nowPinActivity: Activity<NowPinActivityAttributes>?
    
    private init() {}
    
    var isNowPinned: Bool {
        nowPinActivity != nil
    }
    
    // MARK: - Focus Session
    
    func startFocusActivity(
        taskTitle: String,
        sessionNumber: Int,
        sessionEndDate: Date,
        isOnBreak: Bool,
        sessionLabel: String,
        remainingLabel: String,
        isPaused: Bool
    ) {
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

            let attributes = FocusActivityAttributes(taskTitle: taskTitle, sessionNumber: sessionNumber)
            let state = FocusActivityAttributes.ContentState(
                taskTitle: taskTitle,
                sessionEndDate: sessionEndDate,
                isPaused: isPaused,
                isOnBreak: isOnBreak,
                sessionLabel: sessionLabel,
                remainingLabel: remainingLabel
            )

            do {
                focusActivity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: nil),
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
            remainingLabel: remainingLabel
        )
        Task {
            await focusActivity.update(.init(state: state, staleDate: nil))
        }
    }
    
    func endFocusActivity() {
        guard let focusActivity else { return }
        Task {
            await focusActivity.end(nil, dismissalPolicy: .immediate)
        }
        self.focusActivity = nil
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
