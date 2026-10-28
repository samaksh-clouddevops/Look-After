import XCTest
@testable import LookAfterCore

final class StatementPageLayoutTests: XCTestCase {
    func testPositionedColumnsSeparateWithdrawalAndDeposit() {
        var glyphs: [StatementGlyph] = []
        glyphs += place("Withdrawal", x: 405, y: 620)
        glyphs += place("Deposit", x: 512, y: 620)
        glyphs += place("Closing", x: 590, y: 620)
        glyphs += place("01/03/26 UPI-MINU EXAMPLE", x: 34, y: 580)
        glyphs += place("500.00", x: 448, y: 580)
        glyphs += place("170,947.24", x: 590, y: 580)
        glyphs += place("IN004-EXAMPLE", x: 76, y: 560)
        glyphs += place("02/03/26 NEFT CR-EXAMPLE SALARY", x: 34, y: 540)
        glyphs += place("195,779.00", x: 512, y: 540)
        glyphs += place("366,726.24", x: 590, y: 540)

        let csv = StatementPageLayout.csv(pages: [glyphs])
        let lines = MoneyStatementEngine.parse(text: csv, calendar: TestCalendarFixtures.calendar)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].amount, 500)
        XCTAssertEqual(lines[0].direction, .moneyOut)
        XCTAssertTrue(lines[0].note.contains("MINU EXAMPLE"))
        XCTAssertTrue(lines[0].note.contains("IN004-EXAMPLE"))
        XCTAssertEqual(lines[1].amount, 195_779)
        XCTAssertEqual(lines[1].direction, .moneyIn)
    }

    private func place(_ text: String, x: Double, y: Double) -> [StatementGlyph] {
        text.enumerated().map { index, character in
            StatementGlyph(x: x + Double(index) * 4, y: y, character: character)
        }
    }
}
