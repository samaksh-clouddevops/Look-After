import Foundation

public enum StatementDirection: String, Equatable, Sendable, Codable {
    case moneyOut
    case moneyIn
}

public struct StatementLine: Identifiable, Equatable, Sendable, Codable {
    public var id: String
    public var occurredOn: Date
    public var amount: Double
    public var direction: StatementDirection
    public var note: String
    public var kind: SpendKind

    public init(
        id: String = UUID().uuidString,
        occurredOn: Date,
        amount: Double,
        direction: StatementDirection,
        note: String,
        kind: SpendKind = .need
    ) {
        self.id = id
        self.occurredOn = occurredOn
        self.amount = amount
        self.direction = direction
        self.note = note
        self.kind = kind
    }
}

public struct StatementMonthTotal: Equatable, Sendable, Identifiable {
    public var id: String { "\(year)-\(month)" }
    public var year: Int
    public var month: Int
    public var moneyOut: Double
    public var moneyIn: Double
    public var need: Double
    public var extra: Double
}

public struct RepeatingCharge: Equatable, Sendable, Identifiable {
    public var id: String { "\(section.rawValue)-\(Int(amount.rounded()))-\(note)" }
    public var note: String
    public var amount: Double
    public var section: FixedExpenseSection
    public var months: Int
    public var dueDay: Int
}

public struct StatementAnalysis: Equatable, Sendable {
    public var months: [StatementMonthTotal]
    public var averageOut: Double
    public var lines: [StatementLine]
    public var repeating: [RepeatingCharge]
    public var salaryCandidate: Double?
    public var sentence: String
}

public struct StatementTally: Equatable, Sendable {
    public var periodStart: Date
    public var periodEnd: Date
    public var statementOut: Double
    public var loggedOut: Double
    public var matchedCount: Int
    public var missingFromLog: [StatementLine]
    public var missingFromStatement: [DailyExpense]
    public var sentence: String
}

public enum StatementAnomalyKind: String, Equatable, Sendable {
    case unloggedSubscription
    case amountJump
    case duplicateCharge
}

public struct StatementAnomaly: Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: StatementAnomalyKind
    public var note: String
    public var amount: Double
    public var usualAmount: Double?
    public var question: String
}

public struct CardSpendGroup: Equatable, Sendable, Identifiable {
    public var title: String
    public var amount: Double
    public var id: String { title }
}

public struct CardMerchant: Equatable, Sendable, Identifiable {
    public var note: String
    public var amount: Double
    public var kind: SpendKind
    public var id: String { note }
}

/// Totals from one credit-card statement. Swipes are grouped, not saved as daily spends.
public struct CardStatementReport: Equatable, Sendable, Identifiable {
    public var label: String
    public var purchases: Double
    public var fees: Double
    public var payments: Double
    public var installments: Double
    public var amountDue: Double
    public var minimumDue: Double
    public var dueOn: Date?
    public var need: Double
    public var extra: Double
    public var groups: [CardSpendGroup]
    public var merchants: [CardMerchant]
    public var alreadyPlanned: Bool
    public var sentence: String
    public var id: String { "\(label)-\(Int(amountDue.rounded()))-\(Int(minimumDue.rounded()))" }
}

/// One HDFC-style card export, before need and extra labels are filled in.
public struct ParsedCardStatement: Equatable, Sendable {
    public var label: String
    public var amountDue: Double
    public var minimumDue: Double
    public var dueOn: Date?
    public var lines: [StatementLine]
}

public struct CardBillRef: Equatable, Sendable {
    public var title: String
    public var notes: String
    public var amount: Double

    public init(title: String, notes: String, amount: Double) {
        self.title = title
        self.notes = notes
        self.amount = amount
    }
}

public enum MoneyStatementEngine {
    /// Reads CSV, one-line exports, and fixed-column statements such as an HDFC text export. Amounts come only from the file.
    public static func parse(text: String, calendar: Calendar) -> [StatementLine] {
        let trimmed = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if let laidOut = fixedColumns(trimmed, calendar: calendar), !laidOut.isEmpty {
            return laidOut
        }
        let rows = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let table = rows.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !table.isEmpty else { return [] }
        let delimiter: Character = table[0].contains("\t") ? "\t" : (table[0].contains(";") && !table[0].contains(",") ? ";" : ",")
        let cells = table.map { splitRow($0, delimiter: delimiter) }
        if let header = headerMap(cells[0]) {
            return cells.dropFirst().compactMap { row in line(from: row, header: header, calendar: calendar) }
        }
        return table.compactMap { plainLine($0, calendar: calendar) }
    }

    /// Latest six months in the file, grouped and totalled. Repeating rent, EMI, and bills are suggested from the same lines.
    public static func analyse(lines: [StatementLine], calendar: Calendar) -> StatementAnalysis {
        let dated = lines.filter { $0.amount > 0 }
        let months = monthTotals(dated, calendar: calendar)
        let kept = Array(months.suffix(6))
        let keys = Set(kept.map(\.id))
        let keptLines = dated.filter { keys.contains(monthKey($0.occurredOn, calendar: calendar)) }
        let average = kept.isEmpty ? 0 : (kept.reduce(0) { $0 + $1.moneyOut } / Double(kept.count)).rounded()
        let need = kept.reduce(0) { $0 + $1.need }
        let extra = kept.reduce(0) { $0 + $1.extra }
        let repeating = repeatingCharges(keptLines, calendar: calendar)
        let salary = salaryCandidate(keptLines)
        let countWord = countLabel(kept.count)
        let salaryNote = salary.map { " A salary credit of \(plain($0)) shows up." } ?? ""
        let repeatingNote = repeating.isEmpty ? "" : " \(repeating.count) repeating bill\(repeating.count == 1 ? "" : "s") look fixed."
        let sentence = "\(countWord) of spending averages \(plain(average)) a month. Needs \(plain(need)), extras \(plain(extra)).\(repeatingNote)\(salaryNote)"
        return StatementAnalysis(
            months: kept,
            averageOut: average,
            lines: keptLines,
            repeating: repeating,
            salaryCandidate: salary,
            sentence: sentence
        )
    }

    /// Compares statement debits with spends already logged. The period is the latest month in the file that is not after `now`.
    public static func tally(
        lines: [StatementLine],
        expenses: [DailyExpense],
        now: Date,
        calendar: Calendar
    ) -> StatementTally {
        let period = tallyPeriod(lines: lines, now: now, calendar: calendar)
        let statement = lines.filter {
            $0.direction == .moneyOut && $0.amount > 0 && contains($0.occurredOn, period, calendar: calendar)
        }
        let logged = expenses.filter { contains($0.occurredOn, period, calendar: calendar) }
        var usedExpenses = Set<String>()
        var matched = 0
        var missing: [StatementLine] = []
        for line in statement {
            if let expense = logged.first(where: { candidate in
                !usedExpenses.contains(candidate.id) && sameSpend(candidate, line, calendar: calendar)
            }) {
                usedExpenses.insert(expense.id)
                matched += 1
            } else {
                missing.append(line)
            }
        }
        let onlyLogged = logged.filter { !usedExpenses.contains($0.id) }
        let statementOut = statement.reduce(0) { $0 + $1.amount }
        let loggedOut = logged.reduce(0) { $0 + $1.amount }
        let sentence = "Statement shows \(plain(statementOut)) out. Logged spends are \(plain(loggedOut)). \(missing.count) statement lines are not in the log. \(onlyLogged.count) logged spends are not on the statement."
        return StatementTally(
            periodStart: period.start,
            periodEnd: period.end,
            statementOut: statementOut,
            loggedOut: loggedOut,
            matchedCount: matched,
            missingFromLog: missing,
            missingFromStatement: onlyLogged,
            sentence: sentence
        )
    }

    /// One card statement. Purchases, fees, and payments stay separate. Individual swipes are not spend logs.
    public static func analyseCard(
        lines: [StatementLine],
        existingCardBills: [Double]
    ) -> CardStatementReport? {
        guard lines.contains(where: { $0.direction == .moneyOut || $0.direction == .moneyIn }) else { return nil }
        let charges = lines.filter { $0.direction == .moneyOut }
        let payments = lines.filter { $0.direction == .moneyIn }.reduce(0) { $0 + $1.amount }
        let feeLines = charges.filter { isCardFee($0.note) }
        let fees = feeLines.reduce(0) { $0 + $1.amount }
        let purchases = charges.filter { !isCardFee($0.note) }
        let need = purchases.filter { $0.kind == .need }.reduce(0) { $0 + $1.amount }
        let extra = purchases.filter { $0.kind != .need }.reduce(0) { $0 + $1.amount }
        let amountDue = max(0, charges.reduce(0) { $0 + $1.amount } - payments).rounded()
        var groups: [CardSpendGroup] = []
        if need > 0 { groups.append(CardSpendGroup(title: "Needs", amount: need.rounded())) }
        if extra > 0 { groups.append(CardSpendGroup(title: "Extras", amount: extra.rounded())) }
        if fees > 0 { groups.append(CardSpendGroup(title: "Interest and fees", amount: fees.rounded())) }
        let merchants = topMerchants(purchases)
        let already = existingCardBills.contains { abs($0 - amountDue) < max(1, amountDue * 0.02) }
        let largest = merchants.filter { $0.kind != .need }.max { $0.amount < $1.amount } ?? merchants.first
        var sentence = "This card statement comes to \(plain(amountDue)). Needs are \(plain(need)) and extras are \(plain(extra))."
        if fees > 0 {
            sentence += " Interest and fees are \(plain(fees)). Paying \(plain(amountDue)) in full keeps those from growing."
        } else {
            sentence += " Pay \(plain(amountDue)) in full."
        }
        if let largest, largest.amount > 0 {
            sentence += " The largest \(largest.kind == .need ? "need" : "extra") is \(largest.note) at \(plain(largest.amount))."
        }
        if already {
            sentence += " A card bill of this size is already saved."
        }
        return CardStatementReport(
            label: "Card",
            purchases: (need + extra).rounded(),
            fees: fees.rounded(),
            payments: payments.rounded(),
            installments: 0,
            amountDue: amountDue,
            minimumDue: 0,
            dueOn: nil,
            need: need.rounded(),
            extra: extra.rounded(),
            groups: groups,
            merchants: merchants,
            alreadyPlanned: already,
            sentence: sentence
        )
    }

    /// HDFC card exports use `~|~` and print Total Amount Due per card. Each card stays its own statement.
    public static func readHDFCCardStatements(text: String, calendar: Calendar) -> [ParsedCardStatement] {
        let trimmed = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard trimmed.contains("~|~"), trimmed.lowercased().contains("total amount due") else { return [] }
        return hdfcCardBlocks(trimmed).compactMap { block in
            let rows = block.split(separator: "\n", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard let due = labeledAmount(rows, key: "total amount due"), due > 0 else { return nil }
            return ParsedCardStatement(
                label: cardLastFour(rows),
                amountDue: due.rounded(),
                minimumDue: (labeledAmount(rows, key: "minimum amount due") ?? 0).rounded(),
                dueOn: labeledDate(rows, key: "payment due date", calendar: calendar),
                lines: hdfcCardLines(rows, calendar: calendar)
            )
        }
    }

    public static func analyseCard(_ parsed: ParsedCardStatement, existing: [CardBillRef], calendar: Calendar) -> CardStatementReport? {
        let split = cardSpend(parsed.lines)
        let purchases = split.purchases
        let need = purchases.filter { $0.kind == .need }.reduce(0) { $0 + $1.amount }
        let extra = purchases.filter { $0.kind != .need }.reduce(0) { $0 + $1.amount }
        var groups: [CardSpendGroup] = []
        if need > 0 { groups.append(CardSpendGroup(title: "Needs", amount: need.rounded())) }
        if extra > 0 { groups.append(CardSpendGroup(title: "Extras", amount: extra.rounded())) }
        if split.fees > 0 { groups.append(CardSpendGroup(title: "Interest and fees", amount: split.fees.rounded())) }
        if split.installments > 0 { groups.append(CardSpendGroup(title: "EMI instalments", amount: split.installments.rounded())) }
        let merchants = topMerchants(purchases)
        let already = existing.contains { bill in
            let blob = "\(bill.title) \(bill.notes)"
            let sameCard = parsed.label != "Card" && blob.contains(parsed.label)
            let sameAmount = abs(bill.amount - parsed.amountDue) < max(1, parsed.amountDue * 0.02)
            let otherCard = blob.contains(where: \.isNumber) && !sameCard && parsed.label != "Card" && fourDigitTokens(blob).contains { $0 != parsed.label }
            return sameCard || (sameAmount && !otherCard)
        }
        let largest = merchants.filter { $0.kind != .need }.max { $0.amount < $1.amount } ?? merchants.first
        var sentence = "Card \(parsed.label) comes to \(plain(parsed.amountDue))"
        if let dueOn = parsed.dueOn {
            sentence += " due \(plainDay(dueOn, calendar: calendar))"
        }
        sentence += "."
        if parsed.minimumDue > 0 {
            sentence += " The minimum is \(plain(parsed.minimumDue)). Pay \(plain(parsed.amountDue)) in full."
        } else {
            sentence += " Pay \(plain(parsed.amountDue)) in full."
        }
        sentence += " Needs are \(plain(need)) and extras are \(plain(extra))."
        if split.fees > 0 {
            sentence += " Interest and fees are \(plain(split.fees))."
        }
        if split.installments > 0 {
            sentence += " EMI instalments are \(plain(split.installments))."
        }
        if let largest, largest.amount > 0 {
            sentence += " The largest \(largest.kind == .need ? "need" : "extra") is \(largest.note) at \(plain(largest.amount))."
        }
        if already {
            sentence += " Card \(parsed.label) is already saved."
        }
        return CardStatementReport(
            label: parsed.label,
            purchases: (need + extra).rounded(),
            fees: split.fees.rounded(),
            payments: split.payments.rounded(),
            installments: split.installments.rounded(),
            amountDue: parsed.amountDue,
            minimumDue: parsed.minimumDue,
            dueOn: parsed.dueOn,
            need: need.rounded(),
            extra: extra.rounded(),
            groups: groups,
            merchants: merchants,
            alreadyPlanned: already,
            sentence: sentence
        )
    }

    public static func sameSpend(_ expense: DailyExpense, _ line: StatementLine, calendar: Calendar) -> Bool {
        guard abs(expense.amount - line.amount) < 1 else { return false }
        let gap = abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: expense.occurredOn), to: calendar.startOfDay(for: line.occurredOn)).day ?? 99)
        return gap <= 2
    }

    private static func tallyPeriod(lines: [StatementLine], now: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let today = calendar.startOfDay(for: now)
        let dated = lines.filter { $0.direction == .moneyOut && $0.occurredOn <= today }
        let source = dated.isEmpty ? lines : dated
        let monthDate = source.max(by: { $0.occurredOn < $1.occurredOn })?.occurredOn ?? today
        let parts = calendar.dateComponents([.year, .month], from: monthDate)
        let start = calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: 1)) ?? monthDate
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return (start, end)
    }

    /// Subscriptions missing from bills, a charge well above its usual amount, and the same charge twice in one month.
    public static func anomalies(
        lines: [StatementLine],
        bills: [BillItem],
        calendar: Calendar
    ) -> [StatementAnomaly] {
        let outs = lines.filter { $0.direction == .moneyOut && $0.amount > 0 }
        var groups: [String: [StatementLine]] = [:]
        for line in outs {
            let key = merchantKey(line.note)
            guard !key.isEmpty else { continue }
            groups[key, default: []].append(line)
        }
        var found: [StatementAnomaly] = []
        for (key, rows) in groups {
            let latest = rows.max { $0.occurredOn < $1.occurredOn } ?? rows[0]
            let amounts = rows.map(\.amount).sorted()
            let median = amounts[amounts.count / 2]
            if isSubscription(latest.note), !alreadyBilled(latest.note, amount: median, bills: bills) {
                let months = Set(rows.map { monthKey($0.occurredOn, calendar: calendar) }).count
                let span = months > 1 ? " It appears in \(months) months." : ""
                found.append(StatementAnomaly(
                    id: "sub-\(key)",
                    kind: .unloggedSubscription,
                    note: displayName(latest.note),
                    amount: latest.amount.rounded(),
                    usualAmount: nil,
                    question: "Do you still subscribe to \(displayName(latest.note)) for \(plain(latest.amount))?\(span) It is not in your bills."
                ))
            }
            let earlier = rows.filter { $0.id != latest.id }.map(\.amount).sorted()
            if earlier.count >= 2 {
                let usual = earlier[earlier.count / 2]
                if latest.amount >= usual * 1.5, latest.amount - usual >= 200 {
                    found.append(StatementAnomaly(
                        id: "jump-\(key)",
                        kind: .amountJump,
                        note: displayName(latest.note),
                        amount: latest.amount.rounded(),
                        usualAmount: usual.rounded(),
                        question: "\(displayName(latest.note)) is \(plain(latest.amount)), usually \(plain(usual)). Check this charge."
                    ))
                }
            }
            let byMonth = Dictionary(grouping: rows) { monthKey($0.occurredOn, calendar: calendar) }
            for (month, charges) in byMonth where charges.count >= 2 {
                let sorted = charges.sorted { $0.amount < $1.amount }
                let anchor = sorted[0].amount
                let copies = charges.filter { abs($0.amount - anchor) < 1 }
                if copies.count >= 2 {
                    found.append(StatementAnomaly(
                        id: "dup-\(key)-\(month)",
                        kind: .duplicateCharge,
                        note: displayName(charges[0].note),
                        amount: anchor.rounded(),
                        usualAmount: nil,
                        question: "\(displayName(charges[0].note)) was charged \(copies.count) times for \(plain(anchor)) in one month. Check this."
                    ))
                    break
                }
            }
        }
        return Array(found.sorted { rank($0.kind) < rank($1.kind) }.prefix(8))
    }

    private static func rank(_ kind: StatementAnomalyKind) -> Int {
        switch kind {
        case .unloggedSubscription: return 0
        case .duplicateCharge: return 1
        case .amountJump: return 2
        }
    }

    private static func isSubscription(_ note: String) -> Bool {
        let tokens = note.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        if tokens.contains("amazon"), !tokens.contains("prime") { return false }
        if tokens.contains("apple"), tokens.contains("bill") { return true }
        let words = ["netflix", "spotify", "hotstar", "disney", "youtube", "icloud", "itunes", "adobe", "notion", "openai", "chatgpt", "canva", "dropbox", "crunchyroll", "gaana", "wynk", "jiosaavn", "sonyliv", "zee5", "prime", "hulu", "subscription", "membership", "renewal"]
        return words.contains { signal in tokens.contains(signal) }
    }

    private static func alreadyBilled(_ note: String, amount: Double, bills: [BillItem]) -> Bool {
        let key = merchantKey(note)
        guard !key.isEmpty else { return false }
        return bills.contains { bill in
            let hay = merchantKey(bill.title + " " + bill.notes)
            let shared = key.split(separator: " ").contains { token in token.count > 3 && hay.contains(token) }
            return shared && abs(bill.amount - amount) <= max(1, amount * 0.15)
        }
    }

    private static func displayName(_ note: String) -> String {
        let cleaned = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "This charge" }
        return cleaned.count <= 32 ? cleaned : String(cleaned.prefix(32))
    }

    private static func contains(_ date: Date, _ period: (start: Date, end: Date), calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= period.start && day < period.end
    }

    private static func monthTotals(_ lines: [StatementLine], calendar: Calendar) -> [StatementMonthTotal] {
        var buckets: [String: StatementMonthTotal] = [:]
        for line in lines {
            let parts = calendar.dateComponents([.year, .month], from: line.occurredOn)
            guard let year = parts.year, let month = parts.month else { continue }
            let key = "\(year)-\(month)"
            var row = buckets[key] ?? StatementMonthTotal(year: year, month: month, moneyOut: 0, moneyIn: 0, need: 0, extra: 0)
            if line.direction == .moneyIn {
                row.moneyIn += line.amount
            } else {
                row.moneyOut += line.amount
                if line.kind == .extra { row.extra += line.amount } else { row.need += line.amount }
            }
            buckets[key] = row
        }
        return buckets.values.sorted { ($0.year, $0.month) < ($1.year, $1.month) }
    }

    private static func monthKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)"
    }

    private static func repeatingCharges(_ lines: [StatementLine], calendar: Calendar) -> [RepeatingCharge] {
        let outs = lines.filter { $0.direction == .moneyOut }
        var groups: [String: [StatementLine]] = [:]
        for line in outs {
            let key = merchantKey(line.note)
            guard !key.isEmpty else { continue }
            groups[key, default: []].append(line)
        }
        return groups.compactMap { key, rows in
            let section = FixedExpenseSection.matching(key)
            guard section != .other else { return nil }
            let months = Set(rows.map { monthKey($0.occurredOn, calendar: calendar) })
            guard months.count >= 3 else { return nil }
            let amounts = rows.map(\.amount).sorted()
            let median = amounts[amounts.count / 2]
            let days = rows.map { calendar.component(.day, from: $0.occurredOn) }.sorted()
            let due = min(28, max(1, days[days.count / 2]))
            return RepeatingCharge(note: rows[0].note, amount: median.rounded(), section: section, months: months.count, dueDay: due)
        }.sorted { $0.amount > $1.amount }
    }

    private static func salaryCandidate(_ lines: [StatementLine]) -> Double? {
        let credits = lines.filter { line in
            line.direction == .moneyIn && line.note.lowercased().contains("salary")
        }.map(\.amount).sorted()
        guard let amount = credits.last, amount > 0 else { return nil }
        return amount.rounded()
    }

    private static let ignoredMerchantWords: Set<String> = ["com", "www", "upi", "neft", "imps", "ltd", "pvt", "limited", "pos", "india", "mumbai", "bangalore", "bengaluru", "delhi"]

    private static func merchantKey(_ note: String) -> String {
        note.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { word in word.count > 2 && word.rangeOfCharacter(from: .decimalDigits) == nil && !ignoredMerchantWords.contains(word) }
            .prefix(4)
            .joined(separator: " ")
    }

    private static func isCardFee(_ note: String) -> Bool {
        let value = note.lowercased()
        let words = ["interest", "finance charge", "late fee", "late payment", "annual fee", "joining fee", "cash advance", "overlimit", "forex", "foreign markup", "igst", "cgst", "sgst", "emi,int", "markup", "marku", "procng", "fcy"]
        return words.contains { value.contains($0) }
    }

    private static func isCardPayment(_ note: String) -> Bool {
        let value = note.lowercased()
        return value.contains("credit card payment") || value.contains("payment received") || value.contains("autopay")
    }

    private static func isEmiReversal(_ note: String) -> Bool {
        let value = note.lowercased()
        return value.contains("emi") && value.contains("credit")
    }

    private static func isCardInstallment(_ note: String) -> Bool {
        let value = note.lowercased()
        return value.contains("emi,prin") || value.contains("prin nb") || value.contains(",p:")
    }

    private struct CardSpendSplit {
        var purchases: [StatementLine]
        var fees: Double
        var payments: Double
        var installments: Double
    }

    private static func cardSpend(_ lines: [StatementLine]) -> CardSpendSplit {
        let outs = lines.filter { $0.direction == .moneyOut && $0.amount > 0 }
        let credits = lines.filter { $0.direction == .moneyIn && $0.amount > 0 && !isCardPayment($0.note) }
        var used = Set<String>()
        func consume(_ debit: StatementLine, reversalOnly: Bool) -> Bool {
            guard let match = credits.first(where: { credit in
                guard !used.contains(credit.id), abs(credit.amount - debit.amount) < 1 else { return false }
                if reversalOnly { return isEmiReversal(credit.note) }
                let key = merchantKey(debit.note)
                return !key.isEmpty && key == merchantKey(credit.note)
            }) else { return false }
            used.insert(match.id)
            return true
        }
        var remaining: [StatementLine] = []
        for debit in outs {
            if consume(debit, reversalOnly: true) || consume(debit, reversalOnly: false) { continue }
            remaining.append(debit)
        }
        let feeLines = remaining.filter { isCardFee($0.note) }
        let instalments = remaining.filter { !isCardFee($0.note) && isCardInstallment($0.note) }
        let purchases = remaining.filter { !isCardFee($0.note) && !isCardInstallment($0.note) }
        let payments = lines.filter { $0.direction == .moneyIn && isCardPayment($0.note) }.reduce(0) { $0 + $1.amount }
        let cashback = credits.filter { !used.contains($0.id) }.reduce(0) { $0 + $1.amount }
        return CardSpendSplit(
            purchases: purchases,
            fees: feeLines.reduce(0) { $0 + $1.amount },
            payments: payments + cashback,
            installments: instalments.reduce(0) { $0 + $1.amount }
        )
    }

    private static func hdfcCardBlocks(_ text: String) -> [String] {
        let rows = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [[String]] = [[]]
        for row in rows {
            let trimmed = row.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("name~|~"), !blocks[blocks.count - 1].isEmpty {
                blocks.append([row])
            } else {
                blocks[blocks.count - 1].append(row)
            }
        }
        let pieces = blocks.map { $0.joined(separator: "\n") }.filter { $0.lowercased().contains("total amount due") }
        return pieces.isEmpty ? [text] : pieces
    }

    private static func labeledAmount(_ rows: [String], key: String) -> Double? {
        for row in rows {
            let cells = row.components(separatedBy: "~|~").map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 2, cells[0].lowercased() == key else { continue }
            return amount(in: cells[1])
        }
        return nil
    }

    private static func labeledDate(_ rows: [String], key: String, calendar: Calendar) -> Date? {
        for row in rows {
            let cells = row.components(separatedBy: "~|~").map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 2, cells[0].lowercased() == key else { continue }
            return parseDate(String(cells[1].prefix(10)), calendar: calendar)
        }
        return nil
    }

    private static func cardLastFour(_ rows: [String]) -> String {
        for row in rows where row.lowercased().contains("card no") {
            if let last = fourDigitTokens(row).last { return last }
        }
        return "Card"
    }

    private static func fourDigitTokens(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\d{4}"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    private static func hdfcCardLines(_ rows: [String], calendar: Calendar) -> [StatementLine] {
        guard let headerIndex = rows.firstIndex(where: { row in
            let cells = row.lowercased().components(separatedBy: "~|~").map { $0.trimmingCharacters(in: .whitespaces) }
            return cells.contains { $0.contains("description") } && cells.contains { $0.contains("date") }
        }) else { return [] }
        let header = rows[headerIndex].components(separatedBy: "~|~").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let dateIndex = header.firstIndex { $0.contains("date") } ?? 2
        let noteIndex = header.firstIndex { $0.contains("desc") } ?? 3
        let amountIndex = header.firstIndex { $0 == "amt" || ($0.contains("amount") && !$0.contains("due")) } ?? 4
        let flagIndex = header.firstIndex { $0.contains("debit") } ?? 5
        var lines: [StatementLine] = []
        for row in rows.dropFirst(headerIndex + 1) {
            let cells = row.components(separatedBy: "~|~").map { $0.trimmingCharacters(in: .whitespaces) }
            let kind = cells.first?.lowercased() ?? ""
            guard kind == "domestic" || kind == "international" else { break }
            guard dateIndex < cells.count, noteIndex < cells.count, amountIndex < cells.count,
                  let date = parseDate(String(cells[dateIndex].prefix(10)), calendar: calendar),
                  let value = amount(in: cells[amountIndex]), value > 0 else { continue }
            let flag = flagIndex < cells.count ? cells[flagIndex].lowercased() : ""
            let note = cleaned(cells[noteIndex])
            lines.append(StatementLine(
                occurredOn: date,
                amount: value,
                direction: flag == "cr" || flag == "credit" ? .moneyIn : .moneyOut,
                note: note,
                kind: MoneyDecisionEngine.classifyNote(note)
            ))
        }
        return lines
    }

    private static func plainDay(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }

    private static func topMerchants(_ purchases: [StatementLine]) -> [CardMerchant] {
        var buckets: [String: (note: String, amount: Double, kind: SpendKind)] = [:]
        for line in purchases {
            let key = merchantKey(line.note)
            guard !key.isEmpty else { continue }
            var row = buckets[key] ?? (displayName(line.note), 0, line.kind)
            row.amount += line.amount
            if line.kind == .extra { row.kind = .extra }
            buckets[key] = row
        }
        return buckets.values
            .map { CardMerchant(note: $0.note, amount: $0.amount.rounded(), kind: $0.kind) }
            .sorted { $0.amount > $1.amount }
            .prefix(5)
            .map { $0 }
    }

    private struct HeaderMap {
        var date: Int
        var note: Int?
        var debit: Int?
        var credit: Int?
        var amount: Int?
    }

    /// HDFC-style text: a dashed ruler sets the columns. Withdrawal and deposit stay separate from the closing balance, and wrapped narration is kept with the line it belongs to.
    private static func fixedColumns(_ text: String, calendar: Calendar) -> [StatementLine]? {
        let rows = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let ruler = rows.first(where: { dashSpans($0).count >= 5 }),
              dashSpans(ruler).count >= 5 else { return nil }
        let spans = dashSpans(ruler)
        var dateHits = Array(repeating: 0, count: spans.count)
        var moneyHits = Array(repeating: 0, count: spans.count)
        for row in rows where dashSpans(row).count < 5 {
            for index in spans.indices {
                let cell = slice(row, spans[index]).trimmingCharacters(in: .whitespaces)
                if looksLikeShortDate(cell) { dateHits[index] += 1 }
                if wholeMoney(cell) != nil { moneyHits[index] += 1 }
            }
        }
        guard let dateIndex = dateHits.enumerated().filter({ $0.element >= 1 }).min(by: { $0.offset < $1.offset })?.offset else { return nil }
        let moneyIndexes = spans.indices.filter { moneyHits[$0] > 0 && $0 != dateIndex }.sorted()
        guard moneyIndexes.count >= 2,
              let closingIndex = moneyIndexes.max(by: { moneyHits[$0] < moneyHits[$1] }) else { return nil }
        let besideBalance = moneyIndexes.filter { $0 != closingIndex && $0 > dateIndex }
        let movement = Array(besideBalance.suffix(2))
        guard let withdrawalIndex = movement.first else { return nil }
        let depositIndex = movement.count > 1 ? movement.last : nil
        let narrationIndex = spans.indices.first { $0 > dateIndex && $0 < withdrawalIndex }

        var lines: [StatementLine] = []
        var openDate: Date?
        var openNote = ""
        var openDebit = 0.0
        var openCredit = 0.0
        var skippingPage = false

        func close() {
            guard let date = openDate else { return }
            let note = cleaned(openNote)
            if openDebit > 0 {
                lines.append(StatementLine(occurredOn: date, amount: openDebit, direction: .moneyOut, note: note, kind: MoneyDecisionEngine.classifyNote(note)))
            } else if openCredit > 0 {
                lines.append(StatementLine(occurredOn: date, amount: openCredit, direction: .moneyIn, note: note, kind: .need))
            }
            openDate = nil
            openNote = ""
            openDebit = 0
            openCredit = 0
        }

        for row in rows {
            if dashSpans(row).count >= 5 {
                skippingPage = false
                continue
            }
            if isPageFurniture(row) {
                skippingPage = true
                continue
            }
            if skippingPage { continue }
            let dateCell = slice(row, spans[dateIndex]).trimmingCharacters(in: .whitespaces)
            if looksLikeShortDate(dateCell), let date = parseDate(dateCell, calendar: calendar) {
                close()
                openDate = date
                openNote = narrationIndex.map { slice(row, spans[$0]).trimmingCharacters(in: .whitespaces) } ?? ""
                openDebit = wholeMoney(slice(row, spans[withdrawalIndex]).trimmingCharacters(in: .whitespaces)) ?? 0
                if let depositIndex {
                    openCredit = wholeMoney(slice(row, spans[depositIndex]).trimmingCharacters(in: .whitespaces)) ?? 0
                }
                continue
            }
            guard openDate != nil, let narrationIndex else { continue }
            let extra = slice(row, spans[narrationIndex]).trimmingCharacters(in: .whitespaces)
            guard extra.contains(where: \.isLetter) else { continue }
            openNote = openNote.isEmpty ? extra : "\(openNote) \(extra)"
        }
        close()
        return lines.isEmpty ? nil : lines
    }

    private static func isPageFurniture(_ line: String) -> Bool {
        let folded = line.lowercased()
        let markers = ["**continue**", "page no", "hdfc bank", "statement of account"]
        return markers.contains { folded.contains($0) }
    }

    private static func looksLikeShortDate(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 8 || trimmed.count == 10 else { return false }
        return trimmed.range(of: #"^\d{2}/\d{2}/\d{2}(\d{2})?$"#, options: .regularExpression) != nil
    }

    private static func wholeMoney(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.range(of: #"^\d{1,3}(?:,\d{2,3})*\.\d{2}$|^\d+\.\d{2}$"#, options: .regularExpression) != nil else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: ""))
    }

    private static func dashSpans(_ line: String) -> [(Int, Int)] {
        let chars = Array(line)
        var spans: [(Int, Int)] = []
        var index = 0
        while index < chars.count {
            if chars[index] == "-" {
                let start = index
                while index < chars.count, chars[index] == "-" { index += 1 }
                if index - start >= 4 { spans.append((start, index)) }
            } else {
                index += 1
            }
        }
        return spans
    }

    private static func slice(_ line: String, _ span: (Int, Int)) -> String {
        let chars = Array(line)
        guard span.0 < chars.count else { return "" }
        let upper = min(span.1, chars.count)
        guard span.0 < upper else { return "" }
        return String(chars[span.0..<upper])
    }

    private static func headerMap(_ row: [String]) -> HeaderMap? {
        func index(_ words: [String]) -> Int? {
            row.firstIndex { cell in
                let value = cell.lowercased()
                return words.contains { value.contains($0) }
            }
        }
        guard let date = index(["date", "dt"]) else { return nil }
        let debit = index(["debit", "withdrawal", "money out"])
        let credit = index(["credit", "deposit", "money in"])
        let amount = index(["amount", "amt"])
        guard debit != nil || credit != nil || amount != nil else { return nil }
        return HeaderMap(date: date, note: index(["narrat", "desc", "particular", "detail", "remark", "note"]), debit: debit, credit: credit, amount: amount)
    }

    private static func line(from row: [String], header: HeaderMap, calendar: Calendar) -> StatementLine? {
        guard header.date < row.count, let date = parseDate(row[header.date], calendar: calendar) else { return nil }
        let note = header.note.flatMap { $0 < row.count ? row[$0] : nil } ?? ""
        let debit = header.debit.flatMap { amount(in: row, index: $0) } ?? 0
        let credit = header.credit.flatMap { amount(in: row, index: $0) } ?? 0
        if debit > 0 {
            return StatementLine(occurredOn: date, amount: debit, direction: .moneyOut, note: cleaned(note), kind: MoneyDecisionEngine.classifyNote(note))
        }
        if credit > 0 {
            return StatementLine(occurredOn: date, amount: credit, direction: .moneyIn, note: cleaned(note), kind: .need)
        }
        guard let raw = header.amount.flatMap({ $0 < row.count ? row[$0] : nil }) else { return nil }
        return signedLine(date: date, note: note, raw: raw, calendar: calendar)
    }

    private static func plainLine(_ line: String, calendar: Calendar) -> StatementLine? {
        let cells = splitRow(line, delimiter: line.contains("\t") ? "\t" : ",")
        guard let dateCell = cells.first(where: { parseDate($0, calendar: calendar) != nil }),
              let date = parseDate(dateCell, calendar: calendar) else { return nil }
        let note = cells.filter { parseDate($0, calendar: calendar) == nil && amount(in: $0) == nil }.joined(separator: " ")
        let numbers = cells.compactMap { amount(in: $0) }
        guard let value = numbers.first, value > 0 else { return nil }
        let raw = cells.first { amount(in: $0) != nil } ?? ""
        if numbers.count >= 2, !raw.lowercased().contains("dr"), !raw.lowercased().contains("cr") {
            return StatementLine(occurredOn: date, amount: value, direction: direction(note: note, raw: cells.dropFirst().joined(separator: " ")), note: cleaned(note), kind: MoneyDecisionEngine.classifyNote(note))
        }
        return signedLine(date: date, note: note.isEmpty ? line : note, raw: raw, calendar: calendar)
    }

    private static func signedLine(date: Date, note: String, raw: String, calendar: Calendar) -> StatementLine? {
        guard let value = amount(in: raw), value > 0 else { return nil }
        return StatementLine(
            occurredOn: calendar.startOfDay(for: date),
            amount: value,
            direction: direction(note: note, raw: raw),
            note: cleaned(note),
            kind: MoneyDecisionEngine.classifyNote(note)
        )
    }

    private static func direction(note: String, raw: String) -> StatementDirection {
        let text = (note + " " + raw).lowercased()
        if text.contains(" cr") || text.hasSuffix("cr") || text.contains("credit") || text.contains("deposit") || text.contains("salary") || text.contains("refund") {
            return .moneyIn
        }
        return .moneyOut
    }

    private static func amount(in row: [String], index: Int) -> Double? {
        guard index < row.count else { return nil }
        return amount(in: row[index])
    }

    private static func amount(in text: String) -> Double? {
        let pattern = #"(\d{1,3}(?:,\d{2,3})+|\d+)(?:\.\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return Double(text[range].replacingOccurrences(of: ",", with: ""))
    }

    private static func parseDate(_ raw: String, calendar: Calendar) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.rangeOfCharacter(from: .decimalDigits) != nil else { return nil }
        let patterns: [(String, String)] = [
            (#"^\d{4}-\d{2}-\d{2}$"#, "yyyy-MM-dd"),
            (#"^\d{2}/\d{2}/\d{4}$"#, "dd/MM/yyyy"),
            (#"^\d{2}-\d{2}-\d{4}$"#, "dd-MM-yyyy"),
            (#"^\d{2}/\d{2}/\d{2}$"#, "dd/MM/yy"),
            (#"^\d{2}-\d{2}-\d{2}$"#, "dd-MM-yy"),
            (#"^\d{2}-[A-Za-z]{3}-\d{4}$"#, "dd-MMM-yyyy"),
            (#"^\d{2} [A-Za-z]{3} \d{4}$"#, "dd MMM yyyy")
        ]
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.isLenient = false
        for (pattern, format) in patterns {
            guard text.range(of: pattern, options: .regularExpression) != nil else { continue }
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                return calendar.startOfDay(for: date)
            }
        }
        return nil
    }

    private static func splitRow(_ line: String, delimiter: Character) -> [String] {
        var cells: [String] = []
        var current = ""
        var quoted = false
        for character in line {
            if character == "\"" {
                quoted.toggle()
            } else if character == delimiter && !quoted {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func cleaned(_ note: String) -> String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func countLabel(_ count: Int) -> String {
        switch count {
        case 0: return "No months"
        case 1: return "One month"
        case 6: return "Six months"
        default: return "\(count) months"
        }
    }

    private static func plain(_ amount: Double) -> String {
        String(Int(amount.rounded()))
    }
}
