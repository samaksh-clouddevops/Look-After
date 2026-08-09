import Foundation

/// Persists active user day constraints (one per kind per calendar day).
public enum UserDayConstraintStore {
    private static let storageKey = "lifeos_user_day_constraints_v1"

    public static func set(_ constraint: UserDayConstraint, calendar: Calendar = .current) {
        var all = loadAll()
        let day = calendar.startOfDay(for: constraint.day)
        all.removeAll {
            calendar.isDate($0.day, inSameDayAs: day) && $0.kind == constraint.kind
        }
        var stored = constraint
        stored.day = day
        all.append(stored)
        saveAll(all)
    }

    public static func active(kind: UserDayConstraintKind, on day: Date = Date(), calendar: Calendar = .current) -> UserDayConstraint? {
        let target = calendar.startOfDay(for: day)
        return loadAll().first {
            $0.kind == kind && calendar.isDate($0.day, inSameDayAs: target)
        }
    }

    public static func active(on day: Date = Date(), calendar: Calendar = .current) -> [UserDayConstraint] {
        let target = calendar.startOfDay(for: day)
        return loadAll().filter { calendar.isDate($0.day, inSameDayAs: target) }
    }

    public static func clear(kind: UserDayConstraintKind, on day: Date = Date(), calendar: Calendar = .current) {
        let target = calendar.startOfDay(for: day)
        var all = loadAll()
        all.removeAll { $0.kind == kind && calendar.isDate($0.day, inSameDayAs: target) }
        saveAll(all)
    }

    public static func resetForFactoryReset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private static func loadAll() -> [UserDayConstraint] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? SharedFormatters.jsonDecoderSeconds.decode([UserDayConstraint].self, from: data) else {
            return []
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return decoded.filter { calendar.isDate($0.day, inSameDayAs: today) || $0.day >= today }
    }

    private static func saveAll(_ constraints: [UserDayConstraint]) {
        guard let data = try? SharedFormatters.jsonEncoderSeconds.encode(constraints) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
