import XCTest
@testable import LookAfterCore

final class MoneyDecisionEngineTests: XCTestCase {
    private let calendar = TestCalendarFixtures.calendar

    func testZeroSalaryHasNoSnapshot() {
        let plan = MoneyPlan(monthlySalary: 0, userId: "a")
        let snapshot = MoneyDecisionEngine.evaluate(
            plan: plan,
            bills: [],
            expenses: [],
            now: TestCalendarFixtures.date(year: 2026, month: 3, day: 10),
            calendar: calendar
        )
        XCTAssertNil(snapshot)
    }

    func testPaydayBoundaryAndWeeklyExtra() {
        let plan = MoneyPlan(monthlySalary: 80_000, paydayDay: 5, savingsPercent: 10, goalName: "Trip", userId: "a")
        let now = TestCalendarFixtures.date(year: 2026, month: 3, day: 6)
        let snapshot = MoneyDecisionEngine.evaluate(plan: plan, bills: [], expenses: [], now: now, calendar: calendar)
        XCTAssertEqual(snapshot?.safeToSpend, 72_000)
        XCTAssertEqual(snapshot?.savingsTarget, 8_000)
        XCTAssertEqual(snapshot?.savingsKept, 8_000)
        XCTAssertLessThanOrEqual(snapshot?.extraLeftThisWeek ?? 0, snapshot?.safeToSpend ?? 0)
        XCTAssertGreaterThan(snapshot?.extraLeftThisWeek ?? 0, 0)
    }

    func testRentDueBeforePayday() {
        let plan = MoneyPlan(monthlySalary: 80_000, paydayDay: 5, goalName: "Trip", userId: "a")
        let now = TestCalendarFixtures.date(year: 2026, month: 3, day: 1)
        let rent = BillItem(title: "Rent", amount: 18_000, dueDate: TestCalendarFixtures.date(year: 2026, month: 3, day: 2), category: "Rent", userId: "a")
        let snapshot = MoneyDecisionEngine.evaluate(plan: plan, bills: [rent], expenses: [], now: now, calendar: calendar)
        XCTAssertEqual(snapshot?.suggestion, .dueBeforePayday(title: "Rent", amount: 18_000))
    }

    func testExtrasMissTheSavingsGoal() {
        let plan = MoneyPlan(monthlySalary: 80_000, paydayDay: 1, savingsPercent: 10, goalName: "Trip", userId: "a")
        let now = TestCalendarFixtures.date(year: 2026, month: 3, day: 10)
        let extra = DailyExpense(amount: 40_000, kind: .extra, note: "jacket", occurredOn: now, userId: "a")
        let snapshot = MoneyDecisionEngine.evaluate(plan: plan, bills: [], expenses: [extra], now: now, calendar: calendar)
        if case .savingsShortfall(let amount, let goal) = snapshot?.suggestion {
            XCTAssertEqual(goal, "Trip")
            XCTAssertGreaterThan(amount, 0)
        } else {
            XCTFail("expected a savings shortfall, got \(String(describing: snapshot?.suggestion))")
        }
    }

    func testSubscriptionNamesTheLargestOptionalCost() {
        let plan = MoneyPlan(monthlySalary: 50_000, paydayDay: 1, userId: "a")
        let now = TestCalendarFixtures.date(year: 2026, month: 3, day: 2)
        let stream = BillItem(id: "net", title: "Streaming", amount: 8_000, dueDate: now, category: "Subscriptions", userId: "a")
        let snapshot = MoneyDecisionEngine.evaluate(plan: plan, bills: [stream], expenses: [], now: now, calendar: calendar)
        XCTAssertEqual(snapshot?.suggestion, .optionalFixedHigh(title: "Streaming", amount: 8_000))
    }

    func testSubscriptionGrowthUsesThePriorAmount() {
        let plan = MoneyPlan(monthlySalary: 200_000, paydayDay: 1, userId: "a")
        let now = TestCalendarFixtures.date(year: 2026, month: 3, day: 2)
        let stream = BillItem(id: "net", title: "Streaming", amount: 900, dueDate: now, category: "Subscriptions", userId: "a")
        let snapshot = MoneyDecisionEngine.evaluate(
            plan: plan,
            bills: [stream],
            expenses: [],
            priorOptionalAmounts: ["net": 400],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(snapshot?.suggestion, .optionalFixedHigh(title: "Streaming", amount: 900))
    }

    func testFixedCostsOverHalfOfSalary() {
        let plan = MoneyPlan(monthlySalary: 40_000, paydayDay: 1, userId: "a")
        let now = TestCalendarFixtures.date(year: 2026, month: 3, day: 2)
        let rent = BillItem(title: "Rent", amount: 25_000, dueDate: now, category: "Rent", userId: "a")
        let snapshot = MoneyDecisionEngine.evaluate(plan: plan, bills: [rent], expenses: [], now: now, calendar: calendar)
        if case .fixedShareHigh(let share, let title, _) = snapshot?.suggestion {
            XCTAssertGreaterThan(share, 0.5)
            XCTAssertEqual(title, "Rent")
        } else {
            XCTFail("expected a fixed-share card")
        }
    }

    func testShortSleepHidesTheCardAndKeepsTheNumbers() {
        let plan = MoneyPlan(monthlySalary: 40_000, paydayDay: 1, userId: "a")
        let now = TestCalendarFixtures.date(year: 2026, month: 3, day: 2)
        let rent = BillItem(title: "Rent", amount: 25_000, dueDate: now, category: "Rent", userId: "a")
        let snapshot = MoneyDecisionEngine.evaluate(
            plan: plan,
            bills: [rent],
            expenses: [],
            now: now,
            calendar: calendar,
            sleepHours: 4.5
        )
        XCTAssertNil(snapshot?.suggestion)
        XCTAssertEqual(snapshot?.cardHiddenForShortSleep, true)
        XCTAssertNotNil(snapshot?.safeToSpend)
    }

    func testLargeExtraNeedsConfirmationAndMemorySticks() {
        let plan = MoneyPlan(monthlySalary: 80_000, largeExtraThreshold: 2_000, userId: "a")
        XCTAssertTrue(MoneyDecisionEngine.requiresLargeExtraConfirmation(amount: 4_000, kind: .extra, plan: plan))
        XCTAssertFalse(MoneyDecisionEngine.requiresLargeExtraConfirmation(amount: 400, kind: .extra, plan: plan))
        XCTAssertFalse(MoneyDecisionEngine.requiresLargeExtraConfirmation(amount: 9_000, kind: .need, plan: plan))
        var memory: [SpendKindMemory] = []
        memory = MoneyDecisionEngine.remember(note: "Swiggy", kind: .extra, memory: memory)
        XCTAssertEqual(MoneyDecisionEngine.rememberedKind(note: " swiggy ", memory: memory), .extra)
        XCTAssertEqual(MoneyDecisionEngine.classifyNote("cab to office"), .need)
    }

    func testCaptureParsesSalaryRentAndSpend() {
        XCTAssertEqual(MoneyDecisionEngine.parseCapture("I get 80000 on the 1st"), .salary(amount: 80_000, payday: 1))
        XCTAssertEqual(MoneyDecisionEngine.parseCapture("Rent is 18000 on the 5th"), .fixedCost(title: "Rent", amount: 18_000, dueDay: 5))
        XCTAssertEqual(MoneyDecisionEngine.parseCapture("Home loan EMI is 22000 on the 5th"), .fixedCost(title: "Home loan", amount: 22_000, dueDay: 5))
        XCTAssertEqual(MoneyDecisionEngine.role(for: BillItem(title: "Petrol", amount: 3000, dueDate: Date(), category: "Petrol")), .obligation)
        XCTAssertEqual(MoneyDecisionEngine.role(for: BillItem(title: "Home loan", amount: 22000, dueDate: Date(), category: "EMI")), .obligation)
        XCTAssertEqual(FixedExpenseSection.matching("Utilities"), .utilities)
        if case .spend(let amount, let note) = MoneyDecisionEngine.parseCapture("240 on dinner") {
            XCTAssertEqual(amount, 240)
            XCTAssertTrue(note.lowercased().contains("dinner"))
        } else {
            XCTFail("expected a spend draft")
        }
    }

    func testPaySplitsIntoSaveHomeEssentialsLuxuryAndACushion() {
        let plan = MoneyPlan(monthlySalary: 80_000, paydayDay: 1, savingsPercent: 10, goalName: "Trip", userId: "a")
        let now = TestCalendarFixtures.date(year: 2026, month: 3, day: 10)
        let rent = BillItem(title: "Rent", amount: 18_000, dueDate: now, category: "Rent", userId: "a")
        let emi = BillItem(title: "Home loan", amount: 22_000, dueDate: now, category: "EMI", userId: "a")
        let petrol = BillItem(title: "Petrol", amount: 4_000, dueDate: now, category: "Petrol", userId: "a")
        let stream = BillItem(title: "Streaming", amount: 1_000, dueDate: now, category: "Subscriptions", userId: "a")
        let split = MoneyDecisionEngine.split(plan: plan, bills: [rent, emi, petrol, stream], now: now, calendar: calendar)
        let lines = split?.lines ?? []
        XCTAssertEqual(lines.map(\.id), ["save", "home", "bills", "essentials", "luxury", "cushion"])
        XCTAssertEqual(lines.first { $0.id == "save" }?.amount, 8_000)
        XCTAssertEqual(lines.first { $0.id == "home" }?.amount, 40_000)
        XCTAssertEqual(lines.first { $0.id == "bills" }?.amount, 4_000)
        XCTAssertGreaterThanOrEqual(lines.first { $0.id == "luxury" }?.amount ?? 0, 1_000)
        let total = lines.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(total, 80_000, accuracy: 1)
    }

    func testCreditCardPaidNextMonthCountsOnlyThisMonth() {
        let plan = MoneyPlan(monthlySalary: 80_000, paydayDay: 1, savingsPercent: 10, userId: "a")
        let card = BillItem(
            title: "Card",
            amount: 12_000,
            dueDate: TestCalendarFixtures.date(year: 2026, month: 4, day: 15),
            category: "Credit Card",
            userId: "a"
        )
        let march = MoneyDecisionEngine.evaluate(
            plan: plan,
            bills: [card],
            expenses: [],
            now: TestCalendarFixtures.date(year: 2026, month: 3, day: 10),
            calendar: calendar
        )
        let april = MoneyDecisionEngine.evaluate(
            plan: plan,
            bills: [card],
            expenses: [],
            now: TestCalendarFixtures.date(year: 2026, month: 4, day: 10),
            calendar: calendar
        )
        XCTAssertEqual(march?.fixedTotal, 12_000)
        XCTAssertEqual(april?.fixedTotal, 0)
        XCTAssertEqual(
            MoneyDecisionEngine.creditCardBudgetTiming(
                for: card,
                paydayDay: 1,
                now: TestCalendarFixtures.date(year: 2026, month: 3, day: 10),
                calendar: calendar
            ),
            .setAsideThisMonth
        )
    }

    func testPaydayMorningReportsWhatWasKept() {
        let plan = MoneyPlan(monthlySalary: 80_000, paydayDay: 1, savingsPercent: 10, goalName: "Trip", userId: "a")
        let now = TestCalendarFixtures.date(year: 2026, month: 4, day: 1)
        let snapshot = MoneyDecisionEngine.evaluate(plan: plan, bills: [], expenses: [], now: now, calendar: calendar)
        XCTAssertEqual(snapshot?.previousCycleKept, 8_000)
    }

    func testGuideRecommendsFifteenPercentAndThreeMonthsOfRent() {
        let plan = MoneyPlan(monthlySalary: 80_000, paydayDay: 1, goalName: "Trip", userId: "a")
        let rent = BillItem(
            title: "Rent",
            amount: 50_000,
            dueDate: TestCalendarFixtures.date(year: 2026, month: 3, day: 5),
            category: "Rent",
            userId: "a"
        )
        let guide = MoneyDecisionEngine.guide(
            plan: plan,
            bills: [rent],
            now: TestCalendarFixtures.date(year: 2026, month: 3, day: 10),
            calendar: calendar
        )
        XCTAssertEqual(guide?.recommendedSavingsPercent, 15)
        XCTAssertEqual(guide?.recommendedMonthlySave, 12_000)
        XCTAssertEqual(guide?.emergencyTarget, 150_000)
        XCTAssertEqual(guide?.emergencyUsesEstimate, false)
        XCTAssertEqual(guide?.monthsToFund, 13)
        XCTAssertEqual(guide?.dayNumber, 10)
        XCTAssertEqual(guide?.dayCount, 31)
        XCTAssertEqual(guide?.daysLeft, 22)
    }

    func testProjectionSuggestsTheRoomAfterSavingsAndRent() {
        let plan = MoneyPlan(monthlySalary: 80_000, paydayDay: 1, savingsPercent: 10, userId: "a")
        let rent = BillItem(
            title: "Rent",
            amount: 50_000,
            dueDate: TestCalendarFixtures.date(year: 2026, month: 3, day: 5),
            category: "Rent",
            userId: "a"
        )
        let now = TestCalendarFixtures.date(year: 2026, month: 3, day: 10)
        let spent = DailyExpense(amount: 4_000, kind: .need, occurredOn: now, userId: "a")
        let projection = MoneyDecisionEngine.projection(
            plan: plan,
            bills: [rent],
            expenses: [spent],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(projection?.suggestedLimit, 22_000)
        XCTAssertEqual(projection?.limit, 22_000)
        XCTAssertEqual(projection?.usesOwnLimit, false)
        XCTAssertEqual(projection?.spent, 4_000)
        XCTAssertEqual(projection?.projectedSpend, 12_400)
        XCTAssertEqual(projection?.pace, .room)
        XCTAssertEqual(projection?.dailyAllowance, 818)
    }

    func testOwnLimitReplacesTheSuggestionAndFlagsAnOverPace() {
        var plan = MoneyPlan(monthlySalary: 80_000, paydayDay: 1, savingsPercent: 10, userId: "a")
        plan.spendingLimit = 10_000
        let now = TestCalendarFixtures.date(year: 2026, month: 3, day: 10)
        let spent = DailyExpense(amount: 8_000, kind: .extra, occurredOn: now, userId: "a")
        let projection = MoneyDecisionEngine.projection(
            plan: plan,
            bills: [],
            expenses: [spent],
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(projection?.suggestedLimit, 72_000)
        XCTAssertEqual(projection?.limit, 10_000)
        XCTAssertEqual(projection?.usesOwnLimit, true)
        XCTAssertEqual(projection?.projectedSpend, 24_800)
        XCTAssertEqual(projection?.pace, .over)
        XCTAssertEqual(projection?.remaining, 2_000)
        XCTAssertEqual(projection?.dailyAllowance, 91)
    }

    func testSpendOnAnotherDayStaysOutOfThisCycle() {
        let plan = MoneyPlan(monthlySalary: 80_000, paydayDay: 1, userId: "a")
        let now = TestCalendarFixtures.date(year: 2026, month: 3, day: 10)
        let old = DailyExpense(amount: 5_000, kind: .extra, occurredOn: TestCalendarFixtures.date(year: 2026, month: 1, day: 2), userId: "a")
        let snapshot = MoneyDecisionEngine.evaluate(plan: plan, bills: [], expenses: [old], now: now, calendar: calendar)
        XCTAssertEqual(snapshot?.extraSpent, 0)
        XCTAssertEqual(snapshot?.safeToSpend, 72_000)
    }
}
