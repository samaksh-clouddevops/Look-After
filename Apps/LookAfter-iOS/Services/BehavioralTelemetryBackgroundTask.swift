import BackgroundTasks
import Foundation
import LookAfterFeatures
import os

/// Nightly / idle BGProcessingTask that runs TelemetrySynthesizer offline.
enum BehavioralTelemetryBackgroundTask {
    static let identifier = "com.samaksh.flowos.app.behavioral-telemetry"

    private static let logger = Logger(subsystem: "com.lookafter.app", category: "BehavioralTelemetryBG")

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let processing = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(processing)
        }
    }

    /// Prefer overnight idle windows (≈ 3:00 AM local if the system allows).
    static func scheduleNext() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = nextIdleWindowStart()
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.debug("Scheduled behavioral telemetry synthesis")
        } catch {
            logger.error("Failed to schedule telemetry BG task: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func handle(_ task: BGProcessingTask) {
        scheduleNext()

        let completion = BehavioralBGCompletion(task)
        let work = Task { @MainActor in
            let result = await TelemetrySynthesizerService.shared.synthesizeDailyTelemetry()
            logger.info(
                "Synthesized \(result.processedEventCount) events, updated \(result.updatedHashes.count) hashes, flipped \(result.flippedHashes.count)"
            )
            return result
        }

        task.expirationHandler = {
            work.cancel()
            completion.finish(success: false)
        }

        Task {
            do {
                _ = try await work.value
                completion.finish(success: true)
            } catch {
                completion.finish(success: false)
            }
        }
    }

    /// Next local 3:00 AM (or +24h if already past).
    private static func nextIdleWindowStart(now: Date = Date(), calendar: Calendar = .current) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = 3
        comps.minute = 0
        comps.second = 0
        let today3 = calendar.date(from: comps) ?? now.addingTimeInterval(6 * 3600)
        if today3 > now.addingTimeInterval(15 * 60) {
            return today3
        }
        return calendar.date(byAdding: .day, value: 1, to: today3) ?? now.addingTimeInterval(24 * 3600)
    }
}

private final class BehavioralBGCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let task: BGTask

    init(_ task: BGTask) {
        self.task = task
    }

    func finish(success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        task.setTaskCompleted(success: success)
    }
}
