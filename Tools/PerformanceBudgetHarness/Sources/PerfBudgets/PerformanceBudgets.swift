import Foundation

/// Mirror of LookAfterCore.PerformanceBudgets for Linux Docker CI on Windows.
/// Keep in sync with Packages/LookAfterCore/.../PerformanceBudgets.swift
public enum PerformanceBudgets: Sendable {
    public static let focusStateActivationTargetMs: Double = 16
    public static let focusStateActivationHardFailMs: Double = 50
    public static let focusUIOpenTargetMs: Double = 100
    public static let focusUIOpenHardFailMs: Double = 500
    public static let contextRefreshTargetMs: Double = 200
    public static let contextRefreshHardFailMs: Double = 1000
    public static let contextWarmRefreshTargetMs: Double = 150
    public static let contextWarmRefreshHardFailMs: Double = 800
    public static let localSaveReturnTargetMs: Double = 50
    public static let localSaveReturnHardFailMs: Double = 200
    public static let localWrite200TasksTargetMs: Double = 500
    public static let localWrite200TasksHardFailMs: Double = 2000
    public static let localLoad200TasksTargetMs: Double = 200
    public static let localLoad200TasksHardFailMs: Double = 1000
    public static let taskSort100TargetMs: Double = 16
    public static let taskSort100HardFailMs: Double = 50
    public static let taskSort500TargetMs: Double = 50
    public static let taskSort500HardFailMs: Double = 150
    public static let tabTransitionTargetMs: Double = 200
    public static let tabTransitionHardFailMs: Double = 1000
    public static let taskListOpenTargetMs: Double = 500
    public static let taskListOpenHardFailMs: Double = 2000
    public static let multiTabSweepTargetMs: Double = 1500
    public static let multiTabSweepHardFailMs: Double = 4000
    public static let warmLaunchTargetMs: Double = 800
    public static let warmLaunchHardFailMs: Double = 1500

    public static func score(durationMs: Double, targetMs: Double, hardFailMs: Double) -> Double {
        precondition(hardFailMs > targetMs)
        if durationMs <= targetMs { return 100 }
        if durationMs >= hardFailMs * 2 { return 0 }
        if durationMs >= hardFailMs {
            let over = durationMs - hardFailMs
            return max(0, 69 * (1 - over / hardFailMs))
        }
        let span = hardFailMs - targetMs
        let ratio = (durationMs - targetMs) / span
        return 100 - (30 * ratio)
    }

    public static func isAcceptable(_ score: Double, minimum: Double = 70) -> Bool {
        score >= minimum
    }
}
