import Foundation
import Synchronization

/// Single source of truth for the user's medication schedule.
/// PHI is stored in Application Support with Data Protection (not UserDefaults).
public enum MedicationStore {
    public static let userDefaultsKey = "lifeos_medications_list"
    private static let fileName = "medications.json"
    private static let resetDateKey = "lifeos_medications_last_reset"
    /// Avoids repeated JSON decode on hot paths (refreshContext, notifications).
    private static let cachedMedications = Mutex<[Medication]?>(nil)

    public static func load() -> [Medication] {
        if let cached = cachedMedications.withLock({ $0 }) { return cached }
        migrateFromUserDefaultsIfNeeded()
        guard let data = try? Data(contentsOf: fileURL()),
              let medications = try? JSONDecoder().decode([Medication].self, from: data) else {
            cachedMedications.withLock { $0 = [] }
            return []
        }
        cachedMedications.withLock { $0 = medications }
        return medications
    }

    public static func save(_ medications: [Medication]) {
        do {
            let data = try JSONEncoder().encode(medications)
            try writeProtected(data)
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        } catch {
            #if DEBUG
            print("[MedicationStore] save failed: \(error)")
            #endif
        }
        cachedMedications.withLock { $0 = medications }
    }

    /// Reset taken flags at the start of a new day. Safe to call on every timeline rebuild.
    @discardableResult
    public static func resetDailyIfNeeded(now: Date = Date(), calendar: Calendar = .current) -> [Medication] {
        let today = calendar.startOfDay(for: now)
        let lastReset = UserDefaults.standard.object(forKey: resetDateKey) as? Date ?? .distantPast
        let lastResetDay = calendar.startOfDay(for: lastReset)
        var medications = load()
        guard lastResetDay < today else { return medications }
        for index in medications.indices {
            medications[index].isTaken = false
        }
        UserDefaults.standard.set(today, forKey: resetDateKey)
        save(medications)
        return medications
    }

    /// Clears persistence and the in-memory cache.
    public static func reset() {
        cachedMedications.withLock { $0 = nil }
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        try? FileManager.default.removeItem(at: fileURL())
    }

    /// Drops the in-memory cache so the next `load()` re-reads disk.
    /// Call after bulk wipes (factory reset) that bypass `reset()`.
    public static func invalidateCache() {
        cachedMedications.withLock { $0 = nil }
    }

    /// Prompt block for semantic analysis and planning — never invent times outside this list.
    public static func promptBlock(limit: Int = 12) -> String {
        let meds = load().prefix(limit)
        guard !meds.isEmpty else { return "- none configured" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return meds.map { med in
            let taken = med.isTaken ? "taken" : "due"
            return "- id:\(med.id) | \(med.name) | \(formatter.string(from: med.scheduledTime)) | \(taken)"
        }.joined(separator: "\n")
    }

    /// Medical safety rules derived from configured medications.
    public static func medicalSafetyRulesBlock() -> String {
        let meds = load()
        guard !meds.isEmpty else {
            return """
            - No medications configured — classify medication tasks only when title/description clearly indicates meds.
            - Never invent evening medication timing unless explicitly stated in the task.
            """
        }

        var lines = ["CONFIGURED MEDICATIONS (mandatory — use these schedules, never invent times):"]
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        for med in meds {
            lines.append("- \(med.name): scheduled \(formatter.string(from: med.scheduledTime))")
        }
        lines.append("- Match task titles to configured meds when relevant.")
        lines.append("- consequenceOfDelay=medicalRisk for time-sensitive medications.")
        lines.append("- Never invent evening doses unless explicitly in the task title.")
        return lines.joined(separator: "\n")
    }

    private static func migrateFromUserDefaultsIfNeeded() {
        guard !FileManager.default.fileExists(atPath: fileURL().path),
              let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        do {
            try writeProtected(data)
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        } catch {
            #if DEBUG
            print("[MedicationStore] migrate failed: \(error)")
            #endif
        }
    }

    private static func writeProtected(_ data: Data) throws {
        let url = fileURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func fileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LookAfter", isDirectory: true)
        return base.appendingPathComponent(fileName)
    }
}
