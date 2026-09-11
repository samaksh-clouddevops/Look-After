import Foundation

/// Fingerprint + write gate for widget restamps (testable without WidgetKit).
public enum WidgetSyncFingerprint {
    public static func compute(_ snapshot: WidgetSnapshot, now: Date = Date()) -> String {
        let progressBucket = Int((snapshot.pinProgressFraction * 100).rounded(.down) / 5)
        let remainingBucket: String = {
            guard let end = snapshot.pinWindowEnd else { return "na" }
            let minutes = max(0, Int(end.timeIntervalSince(now) / 60))
            return String(minutes)
        }()
        return [
            snapshot.topTaskTitle ?? "",
            String(snapshot.activeTaskCount),
            String(snapshot.completedTodayCount),
            String(snapshot.energyScore),
            snapshot.heroTaskId ?? "",
            snapshot.tasks.map(\.id).joined(separator: ","),
            snapshot.recommendation,
            snapshot.pinScheduleLabel,
            snapshot.pinConstraintLabel,
            String(progressBucket),
            remainingBucket,
            snapshot.pinNextUpSummary,
        ].joined(separator: "|")
    }

    /// `force` bypasses fingerprint equality (NOW complete restamp path).
    public static func shouldWrite(force: Bool, fingerprint: String, lastFingerprint: String?) -> Bool {
        force || fingerprint != lastFingerprint
    }
}
