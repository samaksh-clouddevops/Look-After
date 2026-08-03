import Foundation

/// Single source of truth for the user's medication schedule.
public enum MedicationStore {
    public static let userDefaultsKey = "lifeos_medications_list"

    public static func load() -> [Medication] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let medications = try? JSONDecoder().decode([Medication].self, from: data) else {
            return []
        }
        return medications
    }

    public static func save(_ medications: [Medication]) {
        if let data = try? JSONEncoder().encode(medications) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
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
}
