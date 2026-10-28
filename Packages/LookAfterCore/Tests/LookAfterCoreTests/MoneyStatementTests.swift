import XCTest
@testable import LookAfterCore

final class MoneyStatementTests: XCTestCase {
    private let calendar = TestCalendarFixtures.calendar

    func testCsvKeepsDebitsAndASalaryCredit() {
        let csv = """
        Date,Narration,Debit,Credit
        01/01/2026,Swiggy,500,
        02/01/2026,Salary,,80000
        05/02/2026,House rent,20000,
        03/03/2026,House rent,20000,
        04/04/2026,House rent,20000,
        """
        let lines = MoneyStatementEngine.parse(text: csv, calendar: calendar)
        XCTAssertEqual(lines.count, 5)
        XCTAssertEqual(lines[0].direction, .moneyOut)
        XCTAssertEqual(lines[0].kind, .extra)
        XCTAssertEqual(lines[0].amount, 500)
        XCTAssertEqual(lines[1].direction, .moneyIn)
        XCTAssertEqual(lines[1].amount, 80_000)

        let analysis = MoneyStatementEngine.analyse(lines: lines, calendar: calendar)
        XCTAssertEqual(analysis.months.count, 4)
        XCTAssertEqual(analysis.averageOut, 15_125)
        XCTAssertEqual(analysis.salaryCandidate, 80_000)
        XCTAssertEqual(analysis.repeating.count, 1)
        XCTAssertEqual(analysis.repeating[0].section, .rent)
        XCTAssertEqual(analysis.repeating[0].amount, 20_000)
        XCTAssertEqual(analysis.repeating[0].dueDay, 4)
    }

    func testTallyMarksALoggedSpendAndLeavesTheRest() {
        let csv = """
        Date,Narration,Debit,Credit
        01/03/2026,Swiggy,500,
        02/03/2026,Netflix,300,
        """
        let lines = MoneyStatementEngine.parse(text: csv, calendar: calendar)
        let logged = DailyExpense(
            amount: 500,
            kind: .extra,
            note: "Swiggy",
            occurredOn: TestCalendarFixtures.date(year: 2026, month: 3, day: 1),
            userId: "a"
        )
        let tally = MoneyStatementEngine.tally(
            lines: lines,
            expenses: [logged],
            now: TestCalendarFixtures.date(year: 2026, month: 4, day: 2),
            calendar: calendar
        )
        XCTAssertEqual(tally.matchedCount, 1)
        XCTAssertEqual(tally.missingFromLog.map(\.amount), [300])
        XCTAssertEqual(tally.statementOut, 800)
        XCTAssertEqual(tally.loggedOut, 500)
    }

    func testMoreThanSixMonthsKeepsTheLatestSix() {
        var rows = ["Date,Narration,Debit,Credit"]
        for month in 1...8 {
            rows.append(String(format: "01/%02d/2026,Petrol,1000,", month))
        }
        let lines = MoneyStatementEngine.parse(text: rows.joined(separator: "\n"), calendar: calendar)
        let analysis = MoneyStatementEngine.analyse(lines: lines, calendar: calendar)
        XCTAssertEqual(analysis.months.count, 6)
        XCTAssertEqual(analysis.months.first?.month, 3)
        XCTAssertEqual(analysis.months.last?.month, 8)
        XCTAssertEqual(analysis.averageOut, 1_000)
    }

    func testUnloggedNetflixAsksAndALoggedOneDoesNot() {
        let csv = """
        Date,Narration,Debit,Credit
        04/01/2026,NETFLIX.COM,649,
        04/02/2026,NETFLIX.COM,649,
        04/03/2026,AMAZON PAY,500,
        """
        let lines = MoneyStatementEngine.parse(text: csv, calendar: calendar)
        let open = MoneyStatementEngine.anomalies(lines: lines, bills: [], calendar: calendar)
        XCTAssertEqual(open.map(\.kind), [.unloggedSubscription])
        XCTAssertTrue(open[0].question.contains("649"))
        XCTAssertTrue(open[0].question.lowercased().contains("netflix"))
        XCTAssertTrue(open[0].question.contains("subscribe"))

        let logged = BillItem(
            title: "Netflix",
            amount: 649,
            dueDate: TestCalendarFixtures.date(year: 2026, month: 1, day: 4),
            category: "Subscriptions",
            userId: "a"
        )
        let closed = MoneyStatementEngine.anomalies(lines: lines, bills: [logged], calendar: calendar)
        XCTAssertFalse(closed.contains { $0.kind == .unloggedSubscription })
    }

    func testHDFCFixedColumnsSeparateWithdrawalAndDeposit() {
        let statement = """
        --------  ----------------------------------------  ----------------  --------  ------------------  ------------------  ------------------
        Date      Narration                                 Chq./Ref.No.      Value Dt  Withdrawal Amt.        Deposit Amt.     Closing Balance
        --------  ----------------------------------------  ----------------  --------  ------------------  ------------------  ------------------
        01/03/26  UPI-MINU EXAMPLE-EXAMPLE@UPI-SB           0000606061820508  01/03/26  500.00                                  170,947.24        
                  IN0040023-EXAMPLE-UPI
        **Continue**
        HDFC BANK Ltd.                                     Page No .:   2
        BANGALORE 560048
        --------  ----------------------------------------  ----------------  --------  ------------------  ------------------  ------------------
                  MORE-EXAMPLE-UPI
        02/03/26  NEFT CR-EXAMPLE CO-SALARY                 IN22606123867213  02/03/26                      195,779.00          366,726.24        
        03/03/26  UPI-SHOP EXAMPLE-SHOP@UPI                 0000642880729284  03/03/26  1,009.00                                364,630.24        
        """
        let lines = MoneyStatementEngine.parse(text: statement, calendar: calendar)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].amount, 500)
        XCTAssertEqual(lines[0].direction, .moneyOut)
        XCTAssertTrue(lines[0].note.contains("IN0040023-EXAMPLE-UPI"))
        XCTAssertTrue(lines[0].note.contains("MORE-EXAMPLE-UPI"))
        XCTAssertFalse(lines[0].note.localizedCaseInsensitiveContains("bangalore"))
        XCTAssertEqual(lines[1].amount, 195_779)
        XCTAssertEqual(lines[1].direction, .moneyIn)
        XCTAssertEqual(lines[2].amount, 1_009)
        XCTAssertEqual(lines[2].direction, .moneyOut)
        let firstParts = calendar.dateComponents([.year, .month, .day], from: lines[0].occurredOn)
        XCTAssertEqual(firstParts.year, 2026)
        XCTAssertEqual(firstParts.month, 3)
        XCTAssertEqual(firstParts.day, 1)
    }

    func testAmountJumpAndDoubleCharge() {
        let csv = """
        Date,Narration,Debit,Credit
        01/01/2026,Swiggy,400,
        01/02/2026,Swiggy,400,
        01/03/2026,Swiggy,400,
        20/03/2026,Swiggy,1800,
        05/03/2026,Spotify,119,
        18/03/2026,Spotify,119,
        """
        let lines = MoneyStatementEngine.parse(text: csv, calendar: calendar)
        let found = MoneyStatementEngine.anomalies(lines: lines, bills: [], calendar: calendar)
        let jump = found.first { $0.kind == .amountJump }
        XCTAssertEqual(jump?.usualAmount, 400)
        XCTAssertEqual(jump?.amount, 1800)
        XCTAssertTrue(found.contains { $0.kind == .unloggedSubscription && $0.note.lowercased().contains("spotify") })
        XCTAssertTrue(found.contains { $0.kind == .duplicateCharge && $0.note.lowercased().contains("spotify") })
    }

    func testCardStatementSeparatesNeedsExtrasFeesAndPayments() {
        let csv = """
        Date,Narration,Debit,Credit
        02/03/2026,Swiggy order,800,
        03/03/2026,House rent,1200,
        04/03/2026,Finance charge interest,350,
        05/03/2026,Payment received,,1000
        06/03/2026,Amazon jacket,500,
        """
        let lines = MoneyStatementEngine.parse(text: csv, calendar: calendar)
        let report = MoneyStatementEngine.analyseCard(lines: lines, existingCardBills: [1850])
        XCTAssertEqual(report?.amountDue, 1850)
        XCTAssertEqual(report?.need, 1200)
        XCTAssertEqual(report?.extra, 1300)
        XCTAssertEqual(report?.fees, 350)
        XCTAssertEqual(report?.payments, 1000)
        XCTAssertEqual(report?.alreadyPlanned, true)
        XCTAssertTrue(report?.merchants.contains { $0.note.lowercased().contains("swiggy") } == true)
        let digits = [1850, 1200, 1300, 350]
        for value in digits {
            XCTAssertTrue(report?.sentence.contains(String(value)) == true)
        }
    }

    func testHDFCCardExportsStaySeparateAndUseThePrintedTotal() {
        let text = """
        Name~|~Example
        Payment Due Date~|~09/04/2026
        Total Amount Due~|~6,587.00
        Minimum Amount Due~|~2,818.00
        Card No: 5268 73XX XXXX 7517
        Domestic / International Transactions
        Transaction type~|~Name~|~DATE~|~Description~|~AMT~|~Debit /Credit~|~~|~
        Domestic~|~A ~|~22/02/2026 09:57:11~|~Swiggy Food ~|~800.00~|~~|~~|~
        Domestic~|~A ~|~03/03/2026 16:17:35~|~SWIGGY LIMITED ~|~14,810.63~|~~|~~|~
        Domestic~|~A ~|~05/03/2026 00:00:00~|~AGGREGATOR EMI CREDIT ~|~14,810.63~|~Cr~|~~|~
        Domestic~|~A ~|~06/03/2026 00:00:00~|~IGST-VPS RATE 18.0 ~|~53.82~|~~|~~|~
        Domestic~|~A ~|~07/03/2026 13:30:36~|~CREDIT CARD PAYMENT Net Banking ~|~1,000.00~|~Cr~|~~|~
        Domestic~|~A ~|~20/03/2026 00:00:00~|~OFFUS EMI,PRIN NB:01 ~|~2,388.00~|~~|~~|~
        Domestic~|~A ~|~20/03/2026 00:00:00~|~OFFUS EMI,INT NBR:01 ~|~230.00~|~~|~~|~
        GST Summary
        Name~|~Example
        Payment Due Date~|~10/05/2026
        Total Amount Due~|~1,000.00
        Minimum Amount Due~|~100.00
        Card No: 5522 60XX XXXX 4801
        Domestic / International Transactions
        Transaction type~|~Name~|~DATE~|~Description~|~AMT~|~Debit /Credit~|~~|~
        Domestic~|~A ~|~17/03/2026 20:42:29~|~APPLE INDIA ~|~50,000.00~|~~|~~|~
        GST Summary
        """
        let parsed = MoneyStatementEngine.readHDFCCardStatements(text: text, calendar: calendar)
        XCTAssertEqual(parsed.map(\.label), ["7517", "4801"])
        XCTAssertEqual(parsed.map(\.amountDue), [6587, 1000])
        let saved = [CardBillRef(title: "Credit card 7517", notes: "7517", amount: 100)]
        let first = MoneyStatementEngine.analyseCard(parsed[0], existing: saved, calendar: calendar)
        XCTAssertEqual(first?.amountDue, 6587)
        XCTAssertEqual(first?.minimumDue, 2818)
        XCTAssertEqual(first?.extra, 800)
        XCTAssertEqual(first?.installments, 2388)
        XCTAssertEqual(first?.fees, 284)
        XCTAssertEqual(first?.alreadyPlanned, true)
        XCTAssertTrue(first?.sentence.contains("6587") == true)
        XCTAssertTrue(first?.sentence.contains("2818") == true)
        XCTAssertFalse(first?.merchants.contains { $0.amount == 14811 || $0.amount == 14810 } == true)
        let second = MoneyStatementEngine.analyseCard(parsed[1], existing: saved, calendar: calendar)
        XCTAssertEqual(second?.label, "4801")
        XCTAssertEqual(second?.alreadyPlanned, false)
        XCTAssertEqual(second?.extra, 50_000)
    }
}
