import Foundation
import Synchronization

/// Persists the compiled life model.
public enum LifeModelStore {
    public static let storageKey = "lifeos.lifeModel"
    /// `nil` = not loaded yet; `.some(nil)` = loaded and empty; `.some(model)` = cached model.
    private static let cache = Mutex<LifeModel??>(nil)

    public static func load() -> LifeModel? {
        if let cached = cache.withLock({ $0 }) { return cached }
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let model = try? JSONDecoder().decode(LifeModel.self, from: data) else {
            cache.withLock { $0 = .some(nil) }
            return nil
        }
        cache.withLock { $0 = .some(model) }
        return model
    }

    public static func save(_ model: LifeModel) {
        if let data = try? JSONEncoder().encode(model) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        cache.withLock { $0 = .some(model) }
    }

    public static func reset() {
        cache.withLock { $0 = .some(nil) }
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    /// Drops the in-memory cache so the next `load()` re-reads UserDefaults.
    /// Call after bulk UserDefaults wipes (factory reset) that bypass `reset()`.
    public static func invalidateCache() {
        cache.withLock { $0 = nil }
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
