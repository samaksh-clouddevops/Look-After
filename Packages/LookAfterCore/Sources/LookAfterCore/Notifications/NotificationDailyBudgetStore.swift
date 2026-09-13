import Foundation

public enum NotificationDailyBudgetStore {
    public static let userDefaultsKey = "lookafter_notification_daily_budget"

    public static func load(now: Date = Date(), calendar: Calendar = .current) -> ProactiveDailyBudget {
        let todayKey = ProactiveDailyBudget.dayKey(for: now, calendar: calendar)
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              var budget = try? SharedFormatters.jsonDecoderSeconds.decode(ProactiveDailyBudget.self, from: data) else {
            return ProactiveDailyBudget(dayKey: todayKey)
        }
        if budget.dayKey != todayKey {
            budget = ProactiveDailyBudget(dayKey: todayKey)
            save(budget)
        }
        return budget
    }

    public static func save(_ budget: ProactiveDailyBudget) {
        if let data = try? SharedFormatters.jsonEncoderSeconds.encode(budget) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    /// Records a delivered notification toward the daily cap. Idempotent per `candidateID` so
    /// it is safe to call from both `willPresent` (foreground delivery) and `didReceive`
    /// (background-delivered notification the user later tapped) without double-counting the
    /// same notification.
    public static func recordDelivered(candidateID: String, now: Date = Date(), calendar: Calendar = .current) {
        var budget = load(now: now, calendar: calendar)
        guard !budget.countedCandidateIDs.contains(candidateID) else { return }
        budget.countedCandidateIDs.append(candidateID)
        budget.deliveredCount += 1
        save(budget)
    }

    public static func dismissForToday(candidateID: String, now: Date = Date(), calendar: Calendar = .current) {
        var budget = load(now: now, calendar: calendar)
        if !budget.dismissedCandidateIDs.contains(candidateID) {
            budget.dismissedCandidateIDs.append(candidateID)
        }
        save(budget)
    }

    public static func snooze(candidateID: String, until: Date, now: Date = Date(), calendar: Calendar = .current) {
        var budget = load(now: now, calendar: calendar)
        budget.snoozedCandidateIDs[candidateID] = until
        save(budget)
    }

    public static func resetForFactoryReset() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}
