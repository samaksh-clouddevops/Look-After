import Foundation

/// Structured logging for the Apple Health → FlowOS sync pipeline.
enum HealthSyncLogger {
    private static let prefix = "[HealthSync]"
    
    static func log(_ message: String) {
        print("\(prefix) \(message)")
    }
    
    static func started() {
        log("Started")
    }
    
    static func finished() {
        log("Finished")
    }
    
    static func stageStart(_ stage: String) {
        log("\(stage) — started")
    }
    
    static func stageSuccess(_ stage: String, duration: TimeInterval) {
        log("\(stage) — success (\(formattedDuration(duration)))")
    }
    
    static func stageFailure(_ stage: String, duration: TimeInterval, error: Error) {
        log("\(stage) — failure (\(formattedDuration(duration))): \(error.localizedDescription)")
    }
    
    static func cancelled(_ stage: String) {
        log("\(stage) — cancelled")
    }
    
    @discardableResult
    static func measure<T>(_ stage: String, operation: () async throws -> T) async throws -> T {
        stageStart(stage)
        let start = ContinuousClock.now
        do {
            let value = try await operation()
            let duration = start.duration(to: .now).timeInterval
            stageSuccess(stage, duration: duration)
            return value
        } catch {
            let duration = start.duration(to: .now).timeInterval
            if Task.isCancelled {
                cancelled(stage)
            } else {
                stageFailure(stage, duration: duration, error: error)
            }
            throw error
        }
    }
    
    private static func formattedDuration(_ duration: TimeInterval) -> String {
        String(format: "%.2fs", duration)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
