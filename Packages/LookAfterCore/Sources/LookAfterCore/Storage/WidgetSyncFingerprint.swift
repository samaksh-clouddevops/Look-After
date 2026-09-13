import Foundation

/// Fingerprint + write gate for widget restamps (testable without WidgetKit).
public enum WidgetSyncFingerprint {
    public static func compute(_ snapshot: WidgetSnapshot, now: Date = Date()) -> String {
        let progressBucket = Int((snapshot.pinProgressFraction * 100).rounded(.down) / 5)
        let remainingBucket: String
        if let end = snapshot.pinWindowEnd {
            let minutes = max(0, Int(end.timeIntervalSince(now) / 60))
            remainingBucket = String(minutes)
        } else {
            remainingBucket = "na"
        }

        let title = snapshot.topTaskTitle ?? ""
        let activeCount = String(snapshot.activeTaskCount)
        let completedCount = String(snapshot.completedTodayCount)
        let energy = String(snapshot.energyScore)
        let heroId = snapshot.heroTaskId ?? ""
        let taskIds = snapshot.tasks.map(\.id).joined(separator: ",")
        let sleep = snapshot.sleepHours.map { String(format: "%.1f", $0) } ?? ""
        let steps = snapshot.stepCount.map(String.init) ?? ""
        let hrv = snapshot.hrvMs.map(String.init) ?? ""

        let parts: [String] = [
            title,
            activeCount,
            completedCount,
            energy,
            heroId,
            taskIds,
            snapshot.recommendation,
            snapshot.pinScheduleLabel,
            snapshot.pinConstraintLabel,
            String(progressBucket),
            remainingBucket,
            snapshot.pinNextUpSummary,
            sleep,
            steps,
            hrv,
        ]
        return parts.joined(separator: "|")
    }

    /// `force` bypasses fingerprint equality (NOW complete restamp path).
    public static func shouldWrite(force: Bool, fingerprint: String, lastFingerprint: String?) -> Bool {
        force || fingerprint != lastFingerprint
    }
}
