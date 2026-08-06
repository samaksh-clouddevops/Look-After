import Foundation
import LookAfterCore

/// Owns schedule-driven Live Activity lifecycle.
///
/// Observes `ExecutionBlockSnapshot` transitions and only touches ActivityKit
/// when the active block identity / mode changes or countdown thresholds hit.
@MainActor
final class ActivityStateController {

    static let shared = ActivityStateController()

    private var lastProjectedKey: String?
    private var lastProgressBucket: Int = -1

    /// Progress buckets that force an ActivityKit update (energy-efficient).
    private let criticalProgressBuckets: Set<Int> = [0, 25, 50, 65, 75, 90, 95]

    private init() {}

    /// Project snapshot onto Dynamic Island / Lock Screen.
    /// - Parameter manualFocusActive: When true, ADHD pomodoro owns the slot.
    func apply(snapshot: ExecutionBlockSnapshot, manualFocusActive: Bool) {
        if manualFocusActive {
            lastProjectedKey = nil
            lastProgressBucket = -1
            return
        }

        guard snapshot.surfaceMode.projectsLiveActivity,
              ExecutionBlockResolver.shouldProjectEnvironment(for: snapshot) else {
            if lastProjectedKey != nil {
                LiveActivityManager.shared.endFocusActivity()
                lastProjectedKey = nil
                lastProgressBucket = -1
            }
            return
        }

        let key = projectionKey(for: snapshot)
        let bucket = progressBucket(snapshot.progressFraction)
        let identityChanged = key != lastProjectedKey
        let criticalTick = criticalProgressBuckets.contains(bucket) && bucket != lastProgressBucket

        guard identityChanged || criticalTick || lastProjectedKey == nil else { return }

        LiveActivityManager.shared.applyExecutionBlock(snapshot, manualFocusActive: false)
        lastProjectedKey = key
        lastProgressBucket = bucket
    }

    func end() {
        LiveActivityManager.shared.endFocusActivity()
        lastProjectedKey = nil
        lastProgressBucket = -1
    }

    // MARK: - Private

    private func projectionKey(for snapshot: ExecutionBlockSnapshot) -> String {
        "\(snapshot.taskID ?? snapshot.id)|\(snapshot.surfaceMode.rawValue)|\(snapshot.category.rawValue)"
    }

    private func progressBucket(_ fraction: Double) -> Int {
        Int((fraction * 100).rounded(.down))
    }
}
