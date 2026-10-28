import XCTest
@testable import LookAfterCore

final class StatementWorkbookTests: XCTestCase {
    func testRawDeflateHello() {
        let compressed = Data([0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x07, 0x00])
        let plain = Deflate.inflate(compressed, size: 5)
        XCTAssertEqual(plain, Data("hello".utf8))
    }

    func testStoredXlsxBecomesCsv() throws {
        let shared = """
        <?xml version="1.0"?><sst><si><t>Date</t></si><si><t>Narration</t></si><si><t>Debit</t></si><si><t>Credit</t></si><si><t>NETFLIX.COM</t></si></sst>
        """.data(using: .utf8)!
        let sheet = """
        <?xml version="1.0"?><worksheet><sheetData>
        <row><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c><c r="D1" t="s"><v>3</v></c></row>
        <row><c r="A2"><v>46023</v></c><c r="B2" t="s"><v>4</v></c><c r="C2"><v>649</v></c><c r="D2"></c></row>
        </sheetData></worksheet>
        """.data(using: .utf8)!
        let zip = storedZip([
            "xl/sharedStrings.xml": shared,
            "xl/worksheets/sheet1.xml": sheet
        ])
        let read = StatementWorkbook.read(data: zip, name: "statement.xlsx", password: nil)
        guard case .text(let csv) = read else {
            XCTFail("expected csv")
            return
        }
        XCTAssertTrue(csv.contains("Date,Narration,Debit,Credit"))
        XCTAssertTrue(csv.contains("NETFLIX.COM"))
        XCTAssertTrue(csv.contains("649"))
        let lines = MoneyStatementEngine.parse(text: csv, calendar: TestCalendarFixtures.calendar)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].amount, 649)
        XCTAssertEqual(lines[0].note, "NETFLIX.COM")
    }

    func testLockedPackageAsksForPassword() {
        let zip = storedZip([
            "EncryptionInfo": Data("locked".utf8),
            "EncryptedPackage": Data("secret".utf8)
        ])
        XCTAssertEqual(StatementWorkbook.read(data: zip, name: "statement.xlsx", password: nil), .needsPassword)
        XCTAssertEqual(StatementWorkbook.read(data: zip, name: "statement.xlsx", password: "nope"), .wrongPassword)
    }

    func testPlainTextPassesThrough() {
        let csv = "Date,Narration,Debit,Credit\n01/03/2026,Rent,1000,\n"
        let read = StatementWorkbook.read(data: Data(csv.utf8), name: "statement.txt", password: nil)
        guard case .text(let text) = read else {
            XCTFail("expected text")
            return
        }
        XCTAssertTrue(text.contains("Rent"))
    }

    func testLegacyExcelBecomesCsv() {
        let stream = biff(
            label(row: 0, column: 0, "Date"),
            label(row: 0, column: 1, "Narration"),
            label(row: 0, column: 2, "Debit"),
            number(row: 1, column: 0, 46023),
            label(row: 1, column: 1, "NETFLIX.COM"),
            number(row: 1, column: 2, 649)
        )
        let csv = StatementWorkbook.legacyExcelCSV(stream)
        let lines = MoneyStatementEngine.parse(text: csv, calendar: TestCalendarFixtures.calendar)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].amount, 649)
        XCTAssertEqual(lines[0].note, "NETFLIX.COM")
    }

    private func biff(_ records: Data...) -> Data {
        records.reduce(into: Data()) { $0.append($1) }
    }

    private func label(row: UInt16, column: UInt16, _ text: String) -> Data {
        let bytes = Data(text.utf8)
        var payload = Data()
        payload.appendU16(row)
        payload.appendU16(column)
        payload.appendU16(0)
        payload.appendU16(UInt16(bytes.count))
        payload.append(0)
        payload.append(bytes)
        return record(0x0204, payload)
    }

    private func number(row: UInt16, column: UInt16, _ value: Double) -> Data {
        var payload = Data()
        payload.appendU16(row)
        payload.appendU16(column)
        payload.appendU16(0)
        payload.appendU64(value.bitPattern)
        return record(0x0203, payload)
    }

    private func record(_ type: UInt16, _ payload: Data) -> Data {
        var data = Data()
        data.appendU16(type)
        data.appendU16(UInt16(payload.count))
        data.append(payload)
        return data
    }

    private func storedZip(_ files: [String: Data]) -> Data {
        var local = Data()
        var directory = Data()
        var offset = 0
        for (name, payload) in files {
            let nameBytes = Data(name.utf8)
            var header = Data()
            header.appendU32(0x04034b50)
            header.appendU16(20)
            header.appendU16(0)
            header.appendU16(0)
            header.appendU16(0)
            header.appendU16(0)
            header.appendU32(0)
            header.appendU32(UInt32(payload.count))
            header.appendU32(UInt32(payload.count))
            header.appendU16(UInt16(nameBytes.count))
            header.appendU16(0)
            header.append(nameBytes)
            header.append(payload)
            local.append(header)

            var central = Data()
            central.appendU32(0x02014b50)
            central.appendU16(20)
            central.appendU16(20)
            central.appendU16(0)
            central.appendU16(0)
            central.appendU16(0)
            central.appendU16(0)
            central.appendU32(0)
            central.appendU32(UInt32(payload.count))
            central.appendU32(UInt32(payload.count))
            central.appendU16(UInt16(nameBytes.count))
            central.appendU16(0)
            central.appendU16(0)
            central.appendU16(0)
            central.appendU16(0)
            central.appendU32(0)
            central.appendU32(UInt32(offset))
            central.append(nameBytes)
            directory.append(central)
            offset += header.count
        }
        var end = Data()
        end.appendU32(0x06054b50)
        end.appendU16(0)
        end.appendU16(0)
        end.appendU16(UInt16(files.count))
        end.appendU16(UInt16(files.count))
        end.appendU32(UInt32(directory.count))
        end.appendU32(UInt32(local.count))
        end.appendU16(0)
        return local + directory + end
    }
}

private extension Data {
    mutating func appendU16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendU32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }

    mutating func appendU64(_ value: UInt64) {
        for shift in 0..<8 {
            append(UInt8((value >> (shift * 8)) & 0xFF))
        }
    }
}
