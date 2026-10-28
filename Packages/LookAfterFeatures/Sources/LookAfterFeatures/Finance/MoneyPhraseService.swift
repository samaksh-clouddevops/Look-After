import Foundation
import LookAfterCore
import LookAfterAI

/// Values an Apply button can write into the finance text fields. Empty means the sentence did not say it.
public struct MoneyFieldFill: Equatable, Sendable {
    public var amount: Double?
    public var payday: Int?
    public var dueDay: Int?
    public var note: String?
    public var goalName: String?
    public var savingsPercent: Double?
    public var kind: SpendKind?
    public var emiKind: String?
    public var section: FixedExpenseSection?

    public init() {}

    public var isEmpty: Bool {
        amount == nil && payday == nil && dueDay == nil
            && (note ?? "").isEmpty && (goalName ?? "").isEmpty
            && savingsPercent == nil && kind == nil && emiKind == nil && section == nil
    }
}

public enum MoneyPhraseService {
    /// One sentence from totals already chosen by the engine. Falls back to the template when the model is unavailable.
    public static func phrase(
        _ suggestion: MoneySuggestion,
        salary: Double,
        fixed: Double,
        extraSoFar: Double,
        safeToSpend: Double
    ) async -> String {
        let template = MoneyDecisionEngine.sentence(for: suggestion)
        let prompt = """
        \(template)
        salary \(Int(salary.rounded()))
        fixed \(Int(fixed.rounded()))
        extra so far \(Int(extraSoFar.rounded()))
        safe to spend \(Int(safeToSpend.rounded()))
        """
        do {
            let raw = try await GLMService.shared.sendMessage(
                "Rewrite this as one calm sentence. Keep these numbers. Do not add any other number.\n\(prompt)",
                systemPrompt: "You write one factual money sentence. No shame, no new numbers.",
                history: [],
                maxTokens: 80
            )
            let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, cleaned.count < 240 else { return template }
            return cleaned
        } catch {
            return template
        }
    }

    /// Rewrites the split sentence. The model only sees the six amounts the engine already chose.
    public static func phraseSplit(_ split: MoneySplit) async -> String {
        let numbers = split.lines.map { "\($0.title) \(Int($0.amount.rounded()))" }.joined(separator: "\n")
        do {
            let raw = try await GLMService.shared.sendMessage(
                "Rewrite this as two calm sentences. Keep every number. Do not add a number that is not here.\n\(split.sentence)\n\(numbers)",
                systemPrompt: "You explain a pay split. No shame, no new numbers, no investing advice.",
                history: [],
                maxTokens: 120
            )
            let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, cleaned.count < 320 else { return split.sentence }
            return cleaned
        } catch {
            return split.sentence
        }
    }

    /// Rewrites the savings, emergency-fund, and cycle sentence from numbers the engine already chose.
    public static func phraseGuide(_ guide: MoneyPlanGuide) async -> String {
        let prompt = """
        \(guide.sentence)
        recommended savings percent \(Int(guide.recommendedSavingsPercent.rounded()))
        monthly save \(Int(guide.recommendedMonthlySave.rounded()))
        emergency fund \(Int(guide.emergencyTarget.rounded()))
        months to fund \(guide.monthsToFund)
        day \(guide.dayNumber) of \(guide.dayCount)
        days left \(guide.daysLeft)
        """
        do {
            let raw = try await GLMService.shared.sendMessage(
                "Rewrite this as two calm sentences. Keep every number. Do not add a number that is not here.\n\(prompt)",
                systemPrompt: "You explain a savings and emergency plan. No shame, no investing advice, no new numbers.",
                history: [],
                maxTokens: 140
            )
            let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, cleaned.count < 360 else { return guide.sentence }
            return cleaned
        } catch {
            return guide.sentence
        }
    }

    /// Rewrites the monthly pace sentence from numbers the engine already chose.
    public static func phraseProjection(_ projection: MoneyMonthProjection) async -> String {
        let prompt = """
        \(projection.sentence)
        limit \(Int(projection.limit.rounded()))
        suggested limit \(Int(projection.suggestedLimit.rounded()))
        spent \(Int(projection.spent.rounded()))
        projected \(Int(projection.projectedSpend.rounded()))
        daily \(Int(projection.dailyAllowance.rounded()))
        """
        do {
            let raw = try await GLMService.shared.sendMessage(
                "Rewrite this as two calm sentences. Keep every number. Do not add a number that is not here.\n\(prompt)",
                systemPrompt: "You explain a monthly spending pace. No shame, no new numbers.",
                history: [],
                maxTokens: 140
            )
            let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, cleaned.count < 360 else { return projection.sentence }
            return cleaned
        } catch {
            return projection.sentence
        }
    }

    /// Fields drawn from a sentence. Amounts are kept only when those digits are in the sentence.
    public static func fillFields(from spoken: String) async -> MoneyFieldFill? {
        let trimmed = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var fill = localFill(trimmed)
        if let remote = await remoteFill(trimmed) {
            fill = merge(local: fill, remote: remote, source: trimmed)
        }
        if let note = fill.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            fill.note = await cleanNote(note)
        }
        return fill.isEmpty ? nil : fill
    }

    /// A short note for the text field. Falls back to the words already there.
    public static func cleanNote(_ note: String) async -> String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return trimmed }
        do {
            let raw = try await GLMService.shared.sendMessage(
                "Rewrite this as a short label of at most six words. Do not add a number that is not here. Reply with only the label.\n\(trimmed)",
                systemPrompt: "You shorten a money note. No new numbers.",
                history: [],
                maxTokens: 24
            )
            let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'."))
            guard !cleaned.isEmpty, cleaned.count < 80, !addsNewDigits(cleaned, source: trimmed) else { return trimmed }
            return cleaned
        } catch {
            return trimmed
        }
    }

    private static func localFill(_ text: String) -> MoneyFieldFill {
        var fill = MoneyFieldFill()
        guard let draft = MoneyDecisionEngine.parseCapture(text) else { return fill }
        switch draft {
        case .salary(let amount, let payday):
            fill.amount = amount
            fill.payday = payday
        case .fixedCost(let title, let amount, let dueDay):
            fill.amount = amount
            fill.dueDay = dueDay
            fill.note = title
            fill.section = FixedExpenseSection.matching(title)
            fill.emiKind = emiKind(in: title)
        case .spend(let amount, let note):
            fill.amount = amount
            fill.note = note
            fill.kind = MoneyDecisionEngine.classifyNote(note)
        }
        return fill
    }

    private static func remoteFill(_ text: String) async -> MoneyFieldFill? {
        do {
            let raw = try await GLMService.shared.sendMessage(
                """
                The person wrote:
                \(text)
                Reply with only the lines you can read from that sentence. Copy numbers exactly. Omit a line you cannot see.
                amount:
                note:
                kind: need or extra
                payday:
                due:
                percent:
                goal:
                emi: Home loan, Car, Personal loan, Education, or Other
                section: Rent, Utility bills, Petrol, EMI, Credit Card, Subscriptions, Insurance, or Other
                """,
                systemPrompt: "You copy money details into labeled lines. You never invent a number.",
                history: [],
                maxTokens: 120
            )
            return parseLines(raw)
        } catch {
            return nil
        }
    }

    private static func parseLines(_ raw: String) -> MoneyFieldFill {
        var fill = MoneyFieldFill()
        for line in raw.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[1].isEmpty else { continue }
            let key = parts[0].lowercased()
            let value = parts[1]
            switch key {
            case "amount":
                fill.amount = Double(value.filter { $0.isNumber || $0 == "." })
            case "note":
                fill.note = value
            case "kind":
                if value.lowercased().contains("extra") { fill.kind = .extra }
                else if value.lowercased().contains("need") { fill.kind = .need }
            case "payday":
                fill.payday = Int(value.filter(\.isNumber))
            case "due":
                fill.dueDay = Int(value.filter(\.isNumber))
            case "percent":
                fill.savingsPercent = Double(value.filter { $0.isNumber || $0 == "." })
            case "goal":
                fill.goalName = value
            case "emi":
                fill.emiKind = emiKind(in: value)
            case "section":
                fill.section = FixedExpenseSection.matching(value)
            default:
                break
            }
        }
        return fill
    }

    private static func merge(local: MoneyFieldFill, remote: MoneyFieldFill, source: String) -> MoneyFieldFill {
        var fill = local
        if fill.amount == nil, let amount = remote.amount, numberIsWritten(amount, in: source) {
            fill.amount = amount
        }
        if fill.payday == nil, let day = remote.payday, (1...28).contains(day), numberIsWritten(Double(day), in: source) {
            fill.payday = day
        }
        if fill.dueDay == nil, let day = remote.dueDay, (1...28).contains(day), numberIsWritten(Double(day), in: source) {
            fill.dueDay = day
        }
        if fill.savingsPercent == nil, let percent = remote.savingsPercent, percent >= 0, percent <= 100, numberIsWritten(percent, in: source) {
            fill.savingsPercent = percent
        }
        if let note = remote.note, !note.isEmpty, !addsNewDigits(note, source: source) {
            fill.note = note
        }
        if let goal = remote.goalName, source.localizedCaseInsensitiveContains(goal), !addsNewDigits(goal, source: source) {
            fill.goalName = goal
        }
        if let kind = remote.kind {
            fill.kind = kind
        }
        if fill.emiKind == nil {
            fill.emiKind = remote.emiKind
        }
        if fill.section == nil || fill.section == .other {
            if let section = remote.section { fill.section = section }
        }
        return fill
    }

    private static func emiKind(in text: String) -> String? {
        let lower = text.lowercased()
        if lower.contains("home") { return "Home loan" }
        if lower.contains("car") { return "Car" }
        if lower.contains("personal") { return "Personal loan" }
        if lower.contains("educat") { return "Education" }
        if lower.contains("other") { return "Other" }
        return FixedExpenseSection.emiKinds.first { lower.contains($0.lowercased()) }
    }

    private static func numberIsWritten(_ value: Double, in source: String) -> Bool {
        let token = String(Int(value.rounded()))
        let digits = source.filter(\.isNumber)
        return digits.contains(token)
    }

    private static func addsNewDigits(_ text: String, source: String) -> Bool {
        let pattern = #"\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return true }
        let sourceDigits = source.filter(\.isNumber)
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            guard let span = Range(match.range, in: text) else { continue }
            if !sourceDigits.contains(text[span]) { return true }
        }
        return false
    }

    /// Need or Extra for a note. The on-device list is used immediately, and when the model answers with one word.
    public static func suggestKind(note: String) async -> SpendKind {
        let local = MoneyDecisionEngine.classifyNote(note)
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return local }
        do {
            let raw = try await GLMService.shared.sendMessage(
                "Is this a need or an extra? Need is food, travel, household, and bills. Extra is the rest. Reply with one word: need or extra.\n\(trimmed)",
                systemPrompt: "Reply with only the word need or the word extra.",
                history: [],
                maxTokens: 8
            )
            let word = raw.lowercased()
            if word.contains("extra"), !word.contains("need") { return .extra }
            if word.contains("need"), !word.contains("extra") { return .need }
            return local
        } catch {
            return local
        }
    }

    /// Labels each outflow from the statement. Falls back to the on-device word list when the model is unavailable.
    public static func classifyStatement(_ lines: [StatementLine]) async -> [StatementLine] {
        let notes = Array(Set(lines.filter { $0.direction == .moneyOut }.map { MoneyDecisionEngine.normalizedNote($0.note) }.filter { !$0.isEmpty }))
        var kinds: [String: SpendKind] = [:]
        var index = 0
        while index < notes.count {
            let end = min(index + 25, notes.count)
            let chunk = Array(notes[index..<end])
            index = end
            if let mapped = await classifyChunk(chunk) {
                for (key, kind) in mapped { kinds[key] = kind }
            } else {
                for note in chunk { kinds[note] = MoneyDecisionEngine.classifyNote(note) }
            }
        }
        return lines.map { line in
            guard line.direction == .moneyOut else { return line }
            var copy = line
            copy.kind = kinds[MoneyDecisionEngine.normalizedNote(line.note)] ?? line.kind
            return copy
        }
    }

    /// Turns messy statement text into CSV. The caller still parses and checks the amounts.
    public static func statementTable(from text: String) async -> String? {
        let chunk = String(text.prefix(8_000))
        guard chunk.count > 40 else { return nil }
        do {
            let raw = try await GLMService.shared.sendMessage(
                """
                Turn this bank statement into CSV. Header exactly: Date,Narration,Debit,Credit
                Dates as dd/MM/yyyy. Copy amounts as digits. A debit fills Debit and leaves Credit empty. A credit does the opposite.
                Do not invent a row or an amount.
                \(chunk)
                """,
                systemPrompt: "You copy bank rows into CSV. You never invent an amount.",
                history: [],
                maxTokens: 900
            )
            let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            return nil
        }
    }

    public static func phraseStatement(analysis: StatementAnalysis, tally: StatementTally, questions: [String] = []) async -> String {
        let template = ([analysis.sentence, tally.sentence] + questions).joined(separator: " ")
        do {
            let raw = try await GLMService.shared.sendMessage(
                "Rewrite this as calm sentences. Keep every name and number. Do not add a number that is not here. If a question asks whether someone still subscribes, keep that question.\n\(template)",
                systemPrompt: "You explain a bank statement check. No shame, no new numbers.",
                history: [],
                maxTokens: 180
            )
            let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, cleaned.count < 520 else { return template }
            return cleaned
        } catch {
            return template
        }
    }

    public static func phraseCard(_ report: CardStatementReport) async -> String {
        let template = report.sentence
        do {
            let raw = try await GLMService.shared.sendMessage(
                "Rewrite this card-statement recommendation as two calm sentences. Keep every name and number. Do not add a number, a fee, or a merchant that is not here.\n\(template)",
                systemPrompt: "You phrase a credit-card recommendation. No shame, no new numbers.",
                history: [],
                maxTokens: 160
            )
            let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, cleaned.count < 420, !addsNewDigits(cleaned, source: template) else { return template }
            return cleaned
        } catch {
            return template
        }
    }

    private static func classifyChunk(_ notes: [String]) async -> [String: SpendKind]? {
        let body = notes.joined(separator: "\n")
        do {
            let raw = try await GLMService.shared.sendMessage(
                """
                Each line is a payment. Reply with the same number of lines, in the same order, each ending with |need or |extra.
                Need is food, travel, household, rent, fuel, and bills. Extra is the rest.
                \(body)
                """,
                systemPrompt: "You label payments. Reply only with the lines requested.",
                history: [],
                maxTokens: 400
            )
            let rows = raw.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard rows.count == notes.count else { return nil }
            var mapped: [String: SpendKind] = [:]
            for (note, row) in zip(notes, rows) {
                let lower = row.lowercased()
                if lower.contains("extra"), !lower.contains("need") {
                    mapped[note] = .extra
                } else if lower.contains("need") {
                    mapped[note] = .need
                } else {
                    mapped[note] = MoneyDecisionEngine.classifyNote(note)
                }
            }
            return mapped
        } catch {
            return nil
        }
    }
}
