import Foundation

public struct StatementGlyph: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var character: Character

    public init(x: Double, y: Double, character: Character) {
        self.x = x
        self.y = y
        self.character = character
    }
}

/// Rebuilds a bank-statement PDF whose characters are stored column by column.
/// Withdrawal, deposit, and balance are told apart by where they sit on the page.
public enum StatementPageLayout {
    public static func csv(pages: [[StatementGlyph]]) -> String {
        var rows: [Row] = []
        var withdrawX = 448.0
        var depositX = 512.0
        var closingX = 590.0
        for glyphs in pages {
            let pageLines = lines(from: glyphs)
            for line in pageLines {
                let text = joined(line)
                guard text.localizedCaseInsensitiveContains("withdrawal"),
                      text.localizedCaseInsensitiveContains("deposit") else { continue }
                let tokens = words(in: line)
                if let token = tokens.first(where: { $0.text.localizedCaseInsensitiveContains("withdrawal") }) {
                    withdrawX = token.x
                }
                if let token = tokens.first(where: { $0.text.localizedCaseInsensitiveContains("deposit") }) {
                    depositX = token.x
                }
                if let token = tokens.first(where: { $0.text.localizedCaseInsensitiveContains("closing") }) {
                    closingX = token.x
                }
            }
            let outLimit = depositX - 20
            let inLimit = closingX - 25
            for line in pageLines {
                let ordered = line.sorted { $0.x < $1.x }
                let text = joined(ordered).trimmingCharacters(in: .whitespaces)
                let startX = ordered.first?.x ?? 0
                if text.range(of: #"^\d{2}/\d{2}/\d{2}(\s|$)"#, options: .regularExpression) != nil {
                    var debit = 0.0
                    var credit = 0.0
                    for token in words(in: line) where isMoney(token.text) {
                        let value = Double(token.text.replacingOccurrences(of: ",", with: "")) ?? 0
                        if token.x >= inLimit { continue }
                        if token.x >= outLimit {
                            credit = value
                        } else if token.x >= withdrawX - 40 {
                            debit = value
                        }
                    }
                    guard debit > 0 || credit > 0 else { continue }
                    rows.append(Row(date: String(text.prefix(8)), note: narration(in: line), debit: debit, credit: credit))
                } else if !rows.isEmpty, startX > 60, text.contains(where: \.isLetter), !text.contains(":") {
                    rows[rows.count - 1].note += " " + text
                }
            }
        }
        guard !rows.isEmpty else { return "" }
        var csv = "Date,Narration,Debit,Credit"
        for row in rows {
            let debit = row.debit > 0 ? plain(row.debit) : ""
            let credit = row.credit > 0 ? plain(row.credit) : ""
            csv += "\n\(row.date),\(field(row.note)),\(debit),\(credit)"
        }
        return csv
    }

    private struct Row {
        var date: String
        var note: String
        var debit: Double
        var credit: Double
    }

    private static func lines(from glyphs: [StatementGlyph]) -> [[StatementGlyph]] {
        let sorted = glyphs.sorted { lhs, rhs in
            if abs(lhs.y - rhs.y) > 2.2 { return lhs.y > rhs.y }
            return lhs.x < rhs.x
        }
        var rows: [[StatementGlyph]] = []
        for glyph in sorted {
            if let lastY = rows.last?.map(\.y).max(), abs(lastY - glyph.y) <= 2.2 {
                rows[rows.count - 1].append(glyph)
            } else {
                rows.append([glyph])
            }
        }
        return rows
    }

    private static func words(in glyphs: [StatementGlyph]) -> [(x: Double, text: String)] {
        let ordered = glyphs.sorted { $0.x < $1.x }
        var tokens: [(Double, String)] = []
        var current = ""
        var start = 0.0
        var last = -10_000.0
        for glyph in ordered {
            if current.isEmpty || glyph.x - last < 14 {
                if current.isEmpty { start = glyph.x }
                current.append(glyph.character)
            } else {
                tokens.append((start, current.trimmingCharacters(in: .whitespaces)))
                current = String(glyph.character)
                start = glyph.x
            }
            last = glyph.x
        }
        if !current.isEmpty {
            tokens.append((start, current.trimmingCharacters(in: .whitespaces)))
        }
        return tokens.filter { !$0.1.isEmpty }
    }

    private static func narration(in glyphs: [StatementGlyph]) -> String {
        var parts: [String] = []
        for token in words(in: glyphs) where token.x < 280 {
            var text = token.text
            if text.range(of: #"^\d{2}/\d{2}/\d{2}\s+"#, options: .regularExpression) != nil {
                text = String(text.dropFirst(9))
            }
            guard text.contains(where: \.isLetter) else { continue }
            parts.append(text)
        }
        return parts.joined(separator: " ")
    }

    private static func joined(_ glyphs: [StatementGlyph]) -> String {
        String(glyphs.map(\.character))
    }

    private static func isMoney(_ text: String) -> Bool {
        text.range(of: #"^\d{1,3}(?:,\d{3})*\.\d{2}$|^\d+\.\d{2}$"#, options: .regularExpression) != nil
    }

    private static func field(_ value: String) -> String {
        let cleaned = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if cleaned.contains(",") || cleaned.contains("\"") {
            return "\"\(cleaned.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return cleaned
    }

    private static func plain(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
