import Foundation

/// Canonical performance budgets for automated tests and Instruments validation.
/// Targets = "good" experience. Hard fails = release-blocking regressions.
public enum PerformanceBudgets: Sendable {

    // MARK: - Focus timer (ViewModel + UI)

    public static let focusStateActivationTargetMs: Double = 16
    public static let focusStateActivationHardFailMs: Double = 50
    public static let focusUIOpenTargetMs: Double = 100
    public static let focusUIOpenHardFailMs: Double = 500

    // MARK: - Context / brain

    public static let contextRefreshTargetMs: Double = 200
    public static let contextRefreshHardFailMs: Double = 1000
    public static let contextWarmRefreshTargetMs: Double = 150
    public static let contextWarmRefreshHardFailMs: Double = 800

    // MARK: - Persistence

    public static let localSaveReturnTargetMs: Double = 50
    public static let localSaveReturnHardFailMs: Double = 200
    public static let localWrite200TasksTargetMs: Double = 500
    public static let localWrite200TasksHardFailMs: Double = 2000
    public static let localLoad200TasksTargetMs: Double = 200
    public static let localLoad200TasksHardFailMs: Double = 1000

    // MARK: - Lists

    public static let taskSort100TargetMs: Double = 16
    public static let taskSort100HardFailMs: Double = 50
    public static let taskSort500TargetMs: Double = 50
    public static let taskSort500HardFailMs: Double = 150

    // MARK: - Navigation

    public static let tabTransitionTargetMs: Double = 200
    public static let tabTransitionHardFailMs: Double = 1000
    public static let taskListOpenTargetMs: Double = 500
    public static let taskListOpenHardFailMs: Double = 2000
    public static let multiTabSweepTargetMs: Double = 1500
    public static let multiTabSweepHardFailMs: Double = 4000

    // MARK: - Launch

    public static let warmLaunchTargetMs: Double = 800
    public static let warmLaunchHardFailMs: Double = 1500

    // MARK: - Scoring

    /// Maps a measured duration to a 0–100 score against target/hardFail.
    /// - 100: at or under target
    /// - 70–99: between target and hard fail (linear)
    /// - 0–69: at/over hard fail (still non-zero below 2× hard fail)
    public static func score(durationMs: Double, targetMs: Double, hardFailMs: Double) -> Double {
        precondition(hardFailMs > targetMs)
        if durationMs <= targetMs { return 100 }
        if durationMs >= hardFailMs * 2 { return 0 }
        if durationMs >= hardFailMs {
            let over = durationMs - hardFailMs
            let span = hardFailMs
            return max(0, 69 * (1 - over / span))
        }
        let span = hardFailMs - targetMs
        let ratio = (durationMs - targetMs) / span
        return 100 - (30 * ratio)
    }

    /// Pass if score ≥ acceptable minimum (default 70 = must be under hard fail).
    public static func isAcceptable(_ score: Double, minimum: Double = 70) -> Bool {
        score >= minimum
    }
}
