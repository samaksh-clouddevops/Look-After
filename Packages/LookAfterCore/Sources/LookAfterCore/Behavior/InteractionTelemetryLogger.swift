import Foundation

/// Day-rotated double-buffer logger.
/// Writer → `telemetry_YYYY_MM_DD.json` (today only).
/// Synthesizer → sealed prior-day files only — no shared file lock with the writer.
public final class InteractionTelemetryLogger: ConstraintTelemetryLogging, @unchecked Sendable {
    public static let shared = InteractionTelemetryLogger(directory: nil)

    private let lock = NSLock()
    private var envelope: TelemetryLogEnvelope
    private var activeDayKey: String
    private let directoryURL: URL?
    private let ioQueue = DispatchQueue(label: "com.lookafter.telemetry-log", qos: .utility)
    private let calendar: Calendar
    private let memoryOnly: Bool
    private var memorySealed: [String: TelemetryLogEnvelope] = [:]

    public init(directory: URL?, calendar: Calendar = .current, now: Date = Date()) {
        self.calendar = calendar
        memoryOnly = false
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            directoryURL = directory
        } else if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            directoryURL = support
        } else {
            directoryURL = nil
        }
        activeDayKey = TelemetryLogRotation.dayKey(for: now, calendar: calendar)
        envelope = Self.load(directory: directoryURL, dayKey: activeDayKey)
            ?? .empty(dayKey: activeDayKey, now: now)
    }

    public static func inMemory(
        seed: TelemetryLogEnvelope = .empty(dayKey: "test"),
        sealed: [String: TelemetryLogEnvelope] = [:],
        calendar: Calendar = .current
    ) -> InteractionTelemetryLogger {
        InteractionTelemetryLogger(memorySeed: seed, sealed: sealed, calendar: calendar)
    }

    private init(
        memorySeed: TelemetryLogEnvelope,
        sealed: [String: TelemetryLogEnvelope],
        calendar: Calendar
    ) {
        self.calendar = calendar
        memoryOnly = true
        directoryURL = nil
        activeDayKey = memorySeed.dayKey.isEmpty ? "test" : memorySeed.dayKey
        envelope = memorySeed
        memorySealed = sealed
    }

    public func append(_ event: ConstraintTelemetryEvent) {
        lock.lock()
        rotateIfNeededLocked(now: event.timestamp)
        envelope.append(event, now: event.timestamp)
        let snap = envelope
        let key = activeDayKey
        lock.unlock()
        persistAsync(dayKey: key, snapshot: snap)
    }

    public func snapshot() -> TelemetryLogEnvelope {
        lock.lock()
        defer { lock.unlock() }
        rotateIfNeededLocked(now: Date())
        return envelope
    }

    public func sealedLogs(excludingDayKey: String?) -> [(dayKey: String, envelope: TelemetryLogEnvelope)] {
        lock.lock()
        rotateIfNeededLocked(now: Date())
        let exclude = excludingDayKey ?? activeDayKey
        if memoryOnly {
            let pairs = memorySealed
                .filter { $0.key != exclude }
                .map { (dayKey: $0.key, envelope: $0.value) }
                .sorted { $0.dayKey < $1.dayKey }
            lock.unlock()
            return pairs
        }
        lock.unlock()
        return loadSealedFromDisk(excluding: exclude)
    }

    public func deleteSealedLogs(dayKeys: [String]) {
        lock.lock()
        if memoryOnly {
            dayKeys.forEach { memorySealed.removeValue(forKey: $0) }
            lock.unlock()
            return
        }
        lock.unlock()
        guard let directoryURL else { return }
        for key in dayKeys {
            let url = directoryURL.appendingPathComponent(TelemetryLogRotation.fileName(dayKey: key))
            try? FileManager.default.removeItem(at: url)
        }
    }

    public func replaceAll(_ envelope: TelemetryLogEnvelope) {
        lock.lock()
        self.envelope = envelope
        if !envelope.dayKey.isEmpty { activeDayKey = envelope.dayKey }
        let key = activeDayKey
        let snap = self.envelope
        lock.unlock()
        persistAsync(dayKey: key, snapshot: snap)
    }

    /// Force-seal active day (unit tests).
    public func sealCurrentDayForTesting(advanceTo nextDayKey: String) {
        lock.lock()
        if memoryOnly {
            memorySealed[activeDayKey] = envelope
        } else {
            persistSync(dayKey: activeDayKey, snapshot: envelope)
        }
        activeDayKey = nextDayKey
        envelope = .empty(dayKey: nextDayKey)
        lock.unlock()
    }

    private func rotateIfNeededLocked(now: Date) {
        let today = TelemetryLogRotation.dayKey(for: now, calendar: calendar)
        guard today != activeDayKey else { return }
        if memoryOnly {
            memorySealed[activeDayKey] = envelope
        } else {
            persistSync(dayKey: activeDayKey, snapshot: envelope)
        }
        activeDayKey = today
        envelope = Self.load(directory: directoryURL, dayKey: today)
            ?? .empty(dayKey: today, now: now)
    }

    private func loadSealedFromDisk(excluding: String) -> [(dayKey: String, envelope: TelemetryLogEnvelope)] {
        guard let directoryURL,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directoryURL.path) else {
            return []
        }
        var result: [(String, TelemetryLogEnvelope)] = []
        for name in names where TelemetryLogRotation.isTelemetryFileName(name) {
            guard let key = TelemetryLogRotation.dayKey(fromFileName: name), key != excluding else { continue }
            if let env = Self.load(directory: directoryURL, dayKey: key) {
                result.append((key, env))
            }
        }
        return result.sorted { $0.0 < $1.0 }
    }

    private static func load(directory: URL?, dayKey: String) -> TelemetryLogEnvelope? {
        guard let directory else { return nil }
        let url = directory.appendingPathComponent(TelemetryLogRotation.fileName(dayKey: dayKey))
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? SharedFormatters.jsonDecoderSeconds.decode(TelemetryLogEnvelope.self, from: data)
    }

    private func persistAsync(dayKey: String, snapshot: TelemetryLogEnvelope) {
        guard !memoryOnly, let directoryURL else { return }
        ioQueue.async { Self.write(directory: directoryURL, dayKey: dayKey, snapshot: snapshot) }
    }

    private func persistSync(dayKey: String, snapshot: TelemetryLogEnvelope) {
        guard !memoryOnly, let directoryURL else { return }
        Self.write(directory: directoryURL, dayKey: dayKey, snapshot: snapshot)
    }

    private static func write(directory: URL, dayKey: String, snapshot: TelemetryLogEnvelope) {
        let url = directory.appendingPathComponent(TelemetryLogRotation.fileName(dayKey: dayKey))
        guard let data = try? SharedFormatters.jsonEncoderSeconds.encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}
