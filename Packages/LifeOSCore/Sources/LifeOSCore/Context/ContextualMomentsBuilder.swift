import Foundation

/// Builds context-gated scroll moments and day preview in plain language.
public enum ContextualMomentsBuilder: Sendable {

    public static func buildScrollMoments(
        snapshot: LifeContextSnapshot,
        upcomingBills: [BillItem],
        dayType: ExecutiveDayType
    ) -> [ContextualMoment] {
        var moments: [ContextualMoment] = []

        switch dayType {
        case .grocery:
            if snapshot.unpurchasedShoppingCount > 0 {
                let n = snapshot.unpurchasedShoppingCount
                moments.append(ContextualMoment(
                    message: "\(n) item\(n == 1 ? "" : "s") on your shopping list",
                    icon: "cart.fill"
                ))
            }
        case .billDue:
            if let bill = upcomingBills.first(where: { !$0.isPaid }) {
                moments.append(ContextualMoment(
                    message: "\(bill.title) is due soon",
                    icon: "creditcard.fill"
                ))
            }
        case .poorSleep:
            moments.append(ContextualMoment(
                message: "Take it easy today — last night was rough",
                icon: "bed.double.fill"
            ))
        case .inFlow:
            break
        case .workday:
            if let event = snapshot.calendarAvailability.nextEventTitle,
               let mins = snapshot.calendarAvailability.minutesUntilNextEvent, mins > 0 {
                moments.append(ContextualMoment(
                    message: "\(event) in \(mins) minutes",
                    icon: "calendar"
                ))
            }
        case .weekend:
            moments.append(ContextualMoment(
                message: "Weekend — space for what matters to you",
                icon: "sun.max.fill"
            ))
        case .standard:
            break
        }

        if dayType != .grocery, snapshot.unpurchasedShoppingCount > 0, snapshot.location == .grocery {
            let n = snapshot.unpurchasedShoppingCount
            moments.append(ContextualMoment(
                message: "\(n) item\(n == 1 ? "" : "s") to grab while you're out",
                icon: "cart.fill"
            ))
        }

        if dayType != .billDue, let bill = upcomingBills.first(where: { !$0.isPaid && billIsDueSoon($0) }) {
            moments.append(ContextualMoment(
                message: "\(bill.title) due \(bill.dueLabel)",
                icon: "creditcard.fill"
            ))
        }

        if snapshot.sleepQuality == .poor || snapshot.sleepQuality == .fair, dayType != .poorSleep {
            moments.append(ContextualMoment(
                message: "You didn't sleep well — go easy on yourself",
                icon: "bed.double.fill"
            ))
        }

        return Array(moments.prefix(3))
    }

    public static func buildDayPreview(
        snapshot: LifeContextSnapshot,
        timelineItems: [LifeTimelineEvent],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ContextualMoment] {
        let horizon = now.addingTimeInterval(4 * 3600)
        let relevant = timelineItems
            .filter { !$0.isCompleted && $0.date >= now && $0.date <= horizon }
            .sorted { $0.date < $1.date }
            .prefix(7)

        return relevant.map { item in
            let time = item.date.formatted(date: .omitted, time: .shortened)
            return ContextualMoment(
                id: item.id,
                message: "\(item.title) · \(time)",
                icon: item.kind.icon
            )
        }
    }

    public static func resolveDayType(
        snapshot: LifeContextSnapshot,
        upcomingBills: [BillItem],
        isWeekend: Bool,
        now: Date = Date()
    ) -> ExecutiveDayType {
        if snapshot.lastWorkingContext?.kind == .focusSession { return .inFlow }
        if snapshot.location == .grocery, snapshot.unpurchasedShoppingCount > 0 { return .grocery }
        if upcomingBills.contains(where: { !$0.isPaid && billIsDueWithin($0, days: 1, now: now) }) { return .billDue }
        if snapshot.sleepQuality == .poor || snapshot.sleepQuality == .fair { return .poorSleep }
        if isWeekend { return .weekend }
        if snapshot.calendarAvailability.nextEventTitle != nil { return .workday }
        return .standard
    }
}

private func billIsDueSoon(_ bill: BillItem, now: Date = Date()) -> Bool {
    billIsDueWithin(bill, days: 3, now: now)
}

private func billIsDueWithin(_ bill: BillItem, days: Int, now: Date = Date()) -> Bool {
    let calendar = Calendar.current
    guard let diff = calendar.dateComponents(
        [.day],
        from: calendar.startOfDay(for: now),
        to: calendar.startOfDay(for: bill.dueDate)
    ).day else { return false }
    return diff >= 0 && diff <= days
}

private extension BillItem {
    var dueLabel: String {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: dueDate)
        ).day ?? 0
        switch days {
        case ..<0: return "overdue"
        case 0: return "today"
        case 1: return "tomorrow"
        default: return "in \(days) days"
        }
    }
}
