import Foundation

/// Persists the compiled life model.
public enum LifeModelStore {
    public static let storageKey = "lifeos.lifeModel"

    public static func load() -> LifeModel? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let model = try? JSONDecoder().decode(LifeModel.self, from: data) else {
            return nil
        }
        return model
    }

    public static func save(_ model: LifeModel) {
        if let data = try? JSONEncoder().encode(model) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    public static func reset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    public static var hasCompiledModel: Bool {
        guard let model = load() else { return false }
        return model.hasContent
    }

    /// Syncs office and peak hours from compiled blocks into UserLifeProfile.
    public static func syncProfileFields(from model: LifeModel) {
        var profile = UserLifeProfileStore.load()

        if !model.identity.name.isEmpty {
            profile.preferredName = model.identity.name
        }

        if let office = model.timeBlocks.first(where: {
            $0.label.lowercased().contains("office") || $0.label.lowercased().contains("work")
        }) {
            profile.workStartHour = office.startHour
            profile.workStartMinute = office.startMinute
            profile.workEndHour = office.endHour
            profile.workEndMinute = office.endMinute
        }

        if let creative = model.creativeBlocks().first {
            profile.peakStartHour = creative.startHour
            profile.peakEndHour = creative.endHour
            profile.focusTimePreference = .evening
        }

        if !model.rawMarkdown.isEmpty {
            profile.profileText = model.rawMarkdown
        }

        UserLifeProfileStore.save(profile)
    }
}
