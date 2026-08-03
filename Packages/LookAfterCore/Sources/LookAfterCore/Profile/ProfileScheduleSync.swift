import Foundation

/// Keeps fixed schedule notes and starter tasks aligned with the life profile.
public enum ProfileScheduleSync {

    /// Merges newly extracted fixed commitments into the profile without wiping manual edits.
    public static func enrichFixedScheduleNotes(
        profile: inout UserLifeProfile,
        sections: StructuredLifeProfileSections? = nil
    ) {
        let parsedSections = sections ?? LifeProfileComposer.parse(profile.profileText)
        let extracted = LifeProfileScheduleExtractor.extract(
            profileText: profile.profileText,
            sections: parsedSections
        )

        var merged = splitNotes(profile.fixedScheduleNotes)

        if let fixed = extracted.fixedScheduleNotes {
            merged.append(contentsOf: splitNotes(fixed))
        }

        let valid = Array(Set(merged.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .filter { OnboardingTaskSeeder.canParseFixedNote($0) }

        guard !valid.isEmpty else { return }
        profile.fixedScheduleNotes = valid.joined(separator: "; ")
    }

    private static func splitNotes(_ raw: String) -> [String] {
        raw
            .replacingOccurrences(of: "\n", with: ",")
            .split { $0 == "," || $0 == ";" }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
