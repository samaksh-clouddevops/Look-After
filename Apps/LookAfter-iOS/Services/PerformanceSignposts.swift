import Foundation
import os

/// Performance signposts referenced by Documentation/qa/09-performance-benchmarks.md
enum PerformanceSignposts {
    private static let log = OSLog(subsystem: "com.samaksh.flowos.app", category: "Performance")

    static func beginLaunchToBriefing() -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "LaunchToBriefing", signpostID: id)
        return id
    }

    static func endLaunchToBriefing(_ id: OSSignpostID) {
        os_signpost(.end, log: log, name: "LaunchToBriefing", signpostID: id)
    }

    static func beginOrchestrateBrain() -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "OrchestrateBrain", signpostID: id)
        return id
    }

    static func endOrchestrateBrain(_ id: OSSignpostID) {
        os_signpost(.end, log: log, name: "OrchestrateBrain", signpostID: id)
    }

    static func beginTabTransition() -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "TabTransition", signpostID: id)
        return id
    }

    static func endTabTransition(_ id: OSSignpostID) {
        os_signpost(.end, log: log, name: "TabTransition", signpostID: id)
    }

    static func beginOnboardingStep() -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "OnboardingStep", signpostID: id)
        return id
    }

    static func endOnboardingStep(_ id: OSSignpostID) {
        os_signpost(.end, log: log, name: "OnboardingStep", signpostID: id)
    }
}
