import Foundation
import CryptoKit
import CommonCrypto

public enum StatementFileRead: Equatable, Sendable {
    case text(String)
    case needsPassword
    case wrongPassword
    case unrecognized
}

/// Turns a bank export into text the statement parser can read. Password-protected PDF stays in the app; this covers text and Excel, including an Office password when you supply it.
public enum StatementWorkbook {
    public static func read(data: Data, name: String, password: String?) -> StatementFileRead {
        if data.starts(with: Data("%PDF".utf8)) {
            return .unrecognized
        }
        if data.starts(with: Data([0x50, 0x4B, 0x03, 0x04])) || data.starts(with: Data([0x50, 0x4B, 0x05, 0x06])) {
            return readZipPackage(data, password: password)
        }
        if data.starts(with: Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])) {
            return readCompoundFile(data, password: password)
        }
        if let text = decodedText(data), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(text)
        }
        let ext = (name as NSString).pathExtension.lowercased()
        if ["txt", "csv", "tsv", "text"].contains(ext) {
            return .unrecognized
        }
        return .unrecognized
    }

    private static func readZipPackage(_ data: Data, password: String?) -> StatementFileRead {
        guard let files = ZipArchive.extract(data) else { return .unrecognized }
        let names = Set(files.keys.map { $0.lowercased() })
        if names.contains("encryptedpackage") || names.contains("encryptioninfo") {
            return decryptOfficePackage(files, password: password)
        }
        guard let csv = workbookCSV(files) else { return .unrecognized }
        return csv.isEmpty ? .unrecognized : .text(csv)
    }

    private static func readCompoundFile(_ data: Data, password: String?) -> StatementFileRead {
        guard let files = CompoundFile.extract(data) else {
            if let text = decodedText(data) { return .text(text) }
            return .unrecognized
        }
        let lowered = Dictionary(uniqueKeysWithValues: files.map { ($0.key.lowercased(), $0.value) })
        if lowered["encryptioninfo"] != nil || lowered["encryptedpackage"] != nil {
            return decryptOfficePackage(lowered, password: password)
        }
        if let csv = workbookCSV(files) { return csv.isEmpty ? .unrecognized : .text(csv) }
        if let workbook = lowered["workbook"] ?? lowered["book"] {
            let csv = legacyExcelCSV(workbook)
            if !csv.isEmpty { return .text(csv) }
        }
        if let text = decodedText(data), text.contains(",") || text.contains("\t") { return .text(text) }
        return .unrecognized
    }

    private static func decryptOfficePackage(_ files: [String: Data], password: String?) -> StatementFileRead {
        let lowered = Dictionary(uniqueKeysWithValues: files.map { ($0.key.lowercased(), $0.value) })
        guard let info = lowered["encryptioninfo"], let package = lowered["encryptedpackage"] else {
            return .needsPassword
        }
        guard let password, !password.isEmpty else { return .needsPassword }
        guard let zip = OfficeEncryption.decrypt(info: info, package: package, password: password) else {
            return .wrongPassword
        }
        guard let inner = ZipArchive.extract(zip), let csv = workbookCSV(inner), !csv.isEmpty else {
            return .wrongPassword
        }
        return .text(csv)
    }

    private static func workbookCSV(_ files: [String: Data]) -> String? {
        let lowered = Dictionary(uniqueKeysWithValues: files.map { ($0.key.replacingOccurrences(of: "\\", with: "/").lowercased(), $0.value) })
        guard let sheet = lowered.first(where: { $0.key.hasPrefix("xl/worksheets/sheet") && $0.key.hasSuffix(".xml") })?.value
            ?? lowered["xl/worksheets/sheet1.xml"] else { return nil }
        let shared = lowered["xl/sharedstrings.xml"]
        return SpreadsheetXML.sheetCSV(sheet: sheet, sharedStrings: shared)
    }

    private static func decodedText(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8), text.contains(where: \.isLetter) { return text }
        if data.count >= 2, data[data.startIndex] == 0xFF, data[data.index(after: data.startIndex)] == 0xFE {
            return String(data: data, encoding: .utf16LittleEndian)
        }
        return String(data: data, encoding: .utf16LittleEndian)
    }

    /// Reads a classic Excel 97–2003 Workbook stream (BIFF8) into CSV.
    static func legacyExcelCSV(_ data: Data) -> String {
        var strings: [String] = []
        var cells: [Int: [Int: String]] = [:]
        var offset = 0
        var sst = Data()
        var collectingSST = false
        func finishSST() {
            if collectingSST { strings = sharedStrings(sst) }
            collectingSST = false
            sst.removeAll(keepingCapacity: false)
        }
        while offset + 4 <= data.count {
            let type = Int(readU16(data, offset))
            let length = Int(readU16(data, offset + 2))
            guard offset + 4 + length <= data.count else { break }
            let payload = data.subdata(in: (offset + 4)..<(offset + 4 + length))
            offset += 4 + length
            if collectingSST {
                if type == 0x003C {
                    sst.append(payload)
                    continue
                }
                finishSST()
            }
            switch type {
            case 0x00FC:
                sst = payload
                collectingSST = true
            case 0x0204:
                storeLabel(payload, into: &cells)
            case 0x00FD:
                storeSharedLabel(payload, strings: strings, into: &cells)
            case 0x0203:
                storeNumber(payload, into: &cells)
            case 0x027E:
                storeRK(row: readU16(payload, 0), column: readU16(payload, 2), rk: readU32(payload, 6), into: &cells)
            case 0x00BD:
                storeMulRK(payload, into: &cells)
            default:
                break
            }
        }
        finishSST()
        return gridCSV(cells)
    }

    private static func storeLabel(_ payload: Data, into cells: inout [Int: [Int: String]]) {
        guard payload.count >= 8 else { return }
        let text = unicodeString(payload, offset: 6)?.value ?? ""
        cells[Int(readU16(payload, 0)), default: [:]][Int(readU16(payload, 2))] = text
    }

    private static func storeSharedLabel(_ payload: Data, strings: [String], into cells: inout [Int: [Int: String]]) {
        guard payload.count >= 10 else { return }
        let index = Int(readU32(payload, 6))
        let text = strings.indices.contains(index) ? strings[index] : ""
        cells[Int(readU16(payload, 0)), default: [:]][Int(readU16(payload, 2))] = text
    }

    private static func storeNumber(_ payload: Data, into cells: inout [Int: [Int: String]]) {
        guard payload.count >= 14 else { return }
        let bits = readU64(payload, 6)
        cells[Int(readU16(payload, 0)), default: [:]][Int(readU16(payload, 2))] = plainNumber(Double(bitPattern: bits))
    }

    private static func storeRK(row: UInt16, column: UInt16, rk: UInt32, into cells: inout [Int: [Int: String]]) {
        cells[Int(row), default: [:]][Int(column)] = plainNumber(decodeRK(rk))
    }

    private static func storeMulRK(_ payload: Data, into cells: inout [Int: [Int: String]]) {
        guard payload.count >= 6 else { return }
        let row = readU16(payload, 0)
        var column = Int(readU16(payload, 2))
        var offset = 4
        while offset + 6 <= payload.count - 2 {
            storeRK(row: row, column: UInt16(column), rk: readU32(payload, offset + 2), into: &cells)
            column += 1
            offset += 6
        }
    }

    private static func decodeRK(_ rk: UInt32) -> Double {
        let scaled = (rk & 1) != 0
        let value: Double
        if (rk & 2) != 0 {
            value = Double(Int32(bitPattern: rk) >> 2)
        } else {
            value = Double(bitPattern: UInt64(rk & 0xFFFFFFFC) << 32)
        }
        return scaled ? value / 100 : value
    }

    private static func sharedStrings(_ data: Data) -> [String] {
        guard data.count >= 8 else { return [] }
        let count = Int(readU32(data, 4))
        var cursor = BIFFCursor(data)
        cursor.skip(8)
        var strings: [String] = []
        for _ in 0..<count {
            guard let text = cursor.readRichString() else { break }
            strings.append(text)
        }
        return strings
    }

    private static func unicodeString(_ data: Data, offset: Int) -> (value: String, end: Int)? {
        var cursor = BIFFCursor(data)
        cursor.skip(offset)
        guard let value = cursor.readPlainString() else { return nil }
        return (value, cursor.index)
    }

    private static func gridCSV(_ cells: [Int: [Int: String]]) -> String {
        guard let lastRow = cells.keys.max(), let width = cells.values.map({ ($0.keys.max() ?? -1) + 1 }).max(), width > 0 else { return "" }
        let header = cells[cells.keys.min() ?? 0] ?? [:]
        let dateColumns = Set(header.compactMap { key, value -> Int? in
            value.lowercased().contains("date") ? key : nil
        })
        return (0...lastRow).map { row in
            let line = cells[row] ?? [:]
            return (0..<width).map { column in
                let raw = line[column] ?? ""
                let value = row > 0 && dateColumns.contains(column) ? excelSerial(raw) ?? raw : raw
                return csvCell(value)
            }.joined(separator: ",")
        }.joined(separator: "\n")
    }

    private static func excelSerial(_ raw: String) -> String? {
        guard let serial = Double(raw), serial > 20_000, serial < 80_000 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        guard let epoch = calendar.date(from: DateComponents(year: 1899, month: 12, day: 30)),
              let date = calendar.date(byAdding: .day, value: Int(serial.rounded()), to: epoch) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }

    private static func plainNumber(_ value: Double) -> String {
        if value.rounded() == value { return String(Int(value)) }
        return String(value)
    }

    private static func csvCell(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private static func readU16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(octet(data, offset)) | (UInt16(octet(data, offset + 1)) << 8)
    }

    private static func readU32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(octet(data, offset))
            | (UInt32(octet(data, offset + 1)) << 8)
            | (UInt32(octet(data, offset + 2)) << 16)
            | (UInt32(octet(data, offset + 3)) << 24)
    }

    private static func readU64(_ data: Data, _ offset: Int) -> UInt64 {
        guard offset + 8 <= data.count else { return 0 }
        var value: UInt64 = 0
        for shift in 0..<8 {
            value |= UInt64(octet(data, offset + shift)) << (shift * 8)
        }
        return value
    }
}

private struct BIFFCursor {
    var data: Data
    var index = 0

    init(_ data: Data) { self.data = data }

    mutating func skip(_ count: Int) { index += count }

    mutating func readU8() -> UInt8? {
        guard index < data.count else { return nil }
        let value = octet(data, index)
        index += 1
        return value
    }

    mutating func readU16() -> UInt16? {
        guard index + 2 <= data.count else { return nil }
        let value = UInt16(octet(data, index)) | (UInt16(octet(data, index + 1)) << 8)
        index += 2
        return value
    }

    mutating func readU32() -> UInt32? {
        guard index + 4 <= data.count else { return nil }
        let value = UInt32(octet(data, index))
            | (UInt32(octet(data, index + 1)) << 8)
            | (UInt32(octet(data, index + 2)) << 16)
            | (UInt32(octet(data, index + 3)) << 24)
        index += 4
        return value
    }

    mutating func readPlainString() -> String? { readRichString(allowRuns: false) }

    mutating func readRichString(allowRuns: Bool = true) -> String? {
        guard let count = readU16(), let flags = readU8() else { return nil }
        let rich = allowRuns && (flags & 0x08) != 0
        let extended = allowRuns && (flags & 0x04) != 0
        let runs = rich ? Int(readU16() ?? 0) : 0
        let extra = extended ? Int(readU32() ?? 0) : 0
        guard let text = readCharacters(count: Int(count), wide: (flags & 0x01) != 0) else { return nil }
        index += runs * 4
        index += extra
        return text
    }

    mutating func readCharacters(count: Int, wide: Bool) -> String? {
        let size = count * (wide ? 2 : 1)
        guard index + size <= data.count else { return nil }
        let bytes = data.subdata(in: index..<(index + size))
        index += size
        if wide { return String(data: bytes, encoding: .utf16LittleEndian) }
        return String(bytes: bytes, encoding: .isoLatin1)
    }
}

enum SpreadsheetXML {
    static func sheetCSV(sheet: Data, sharedStrings: Data?) -> String {
        let strings = sharedStrings.map(sharedStringTable) ?? []
        let rows = sheetRows(sheet, strings: strings)
        guard !rows.isEmpty else { return "" }
        let width = rows.map(\.count).max() ?? 0
        let dateColumns = dateColumnIndexes(rows.first ?? [])
        return rows.enumerated().map { index, row in
            (0..<width).map { column in
                let raw = column < row.count ? row[column] : ""
                let value = index > 0 && dateColumns.contains(column) ? excelDate(raw) ?? raw : raw
                return csvField(value)
            }.joined(separator: ",")
        }.joined(separator: "\n")
    }

    private static func sharedStringTable(_ data: Data) -> [String] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var values: [String] = []
        let pieces = xml.components(separatedBy: "<si")
        for piece in pieces.dropFirst() {
            var text = ""
            var remainder = piece
            while let start = remainder.range(of: "<t"),
                  let openEnd = remainder.range(of: ">", range: start.lowerBound..<remainder.endIndex),
                  let close = remainder.range(of: "</t>", range: openEnd.upperBound..<remainder.endIndex) {
                text += String(remainder[openEnd.upperBound..<close.lowerBound])
                remainder = String(remainder[close.upperBound...])
            }
            values.append(unescape(text))
        }
        return values
    }

    private static func sheetRows(_ data: Data, strings: [String]) -> [[String]] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var rows: [[String]] = []
        let rowPieces = xml.components(separatedBy: "<row")
        for piece in rowPieces.dropFirst() {
            var cells: [Int: String] = [:]
            var remainder = piece
            while let cellStart = remainder.range(of: "<c "),
                  let cellEnd = remainder.range(of: "</c>", range: cellStart.upperBound..<remainder.endIndex) {
                let cell = String(remainder[cellStart.lowerBound..<cellEnd.upperBound])
                if let ref = attribute("r", in: cell), let column = columnIndex(ref) {
                    cells[column] = cellValue(cell, strings: strings)
                }
                remainder = String(remainder[cellEnd.upperBound...])
            }
            if !cells.isEmpty {
                let width = (cells.keys.max() ?? 0) + 1
                rows.append((0..<width).map { cells[$0] ?? "" })
            }
        }
        return rows
    }

    private static func cellValue(_ cell: String, strings: [String]) -> String {
        guard let start = cell.range(of: "<v"),
              let open = cell.range(of: ">", range: start.lowerBound..<cell.endIndex),
              let close = cell.range(of: "</v>", range: open.upperBound..<cell.endIndex) else { return "" }
        let raw = unescape(String(cell[open.upperBound..<close.lowerBound]))
        if cell.contains("t=\"s\""), let index = Int(raw), strings.indices.contains(index) {
            return strings[index]
        }
        return raw
    }

    private static func columnIndex(_ ref: String) -> Int? {
        var value = 0
        var found = false
        for scalar in ref.unicodeScalars {
            guard scalar.properties.isAlphabetic else { break }
            found = true
            value = value * 26 + Int(scalar.value - 64)
        }
        return found ? value - 1 : nil
    }

    private static func attribute(_ name: String, in xml: String) -> String? {
        guard let range = xml.range(of: "\(name)=\"") else { return nil }
        let rest = xml[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }

    private static func dateColumnIndexes(_ header: [String]) -> Set<Int> {
        Set(header.enumerated().compactMap { index, title in
            let lower = title.lowercased()
            return lower.contains("date") || lower == "dt" ? index : nil
        })
    }

    private static func excelDate(_ raw: String) -> String? {
        guard let serial = Double(raw), serial > 20_000, serial < 80_000 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        guard let epoch = calendar.date(from: DateComponents(year: 1899, month: 12, day: 30)),
              let date = calendar.date(byAdding: .day, value: Int(serial.rounded()), to: epoch) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }

    private static func csvField(_ value: String) -> String {
        let decoded = unescape(value)
        if decoded.contains(",") || decoded.contains("\"") || decoded.contains("\n") {
            return "\"\(decoded.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return decoded
    }

    private static func unescape(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#10;", with: " ")
    }
}

enum ZipArchive {
    static func extract(_ data: Data) -> [String: Data]? {
        guard let eocd = endOfCentralDirectory(data) else { return nil }
        var files: [String: Data] = [:]
        var offset = eocd.directory
        for _ in 0..<eocd.count {
            guard offset + 46 <= data.count else { return nil }
            guard read32(data, offset) == 0x02014b50 else { return nil }
            let method = Int(read16(data, offset + 10))
            let compressed = Int(read32(data, offset + 20))
            let uncompressed = Int(read32(data, offset + 24))
            let nameLength = Int(read16(data, offset + 28))
            let extraLength = Int(read16(data, offset + 30))
            let commentLength = Int(read16(data, offset + 32))
            let local = Int(read32(data, offset + 42))
            let nameStart = offset + 46
            guard nameStart + nameLength <= data.count else { return nil }
            let name = String(data: data.subdata(in: nameStart..<(nameStart + nameLength)), encoding: .utf8) ?? ""
            offset = nameStart + nameLength + extraLength + commentLength
            if name.hasSuffix("/") { continue }
            guard let bytes = localBytes(data, local: local, method: method, compressed: compressed, uncompressed: uncompressed) else {
                continue
            }
            files[name] = bytes
        }
        return files
    }

    private static func localBytes(_ data: Data, local: Int, method: Int, compressed: Int, uncompressed: Int) -> Data? {
        guard local + 30 <= data.count, read32(data, local) == 0x04034b50 else { return nil }
        let nameLength = Int(read16(data, local + 26))
        let extraLength = Int(read16(data, local + 28))
        let start = local + 30 + nameLength + extraLength
        let end = start + compressed
        guard end <= data.count else { return nil }
        let payload = data.subdata(in: start..<end)
        if method == 0 { return payload }
        if method == 8 { return Deflate.inflate(payload, size: max(uncompressed, payload.count)) }
        return nil
    }

    private static func endOfCentralDirectory(_ data: Data) -> (directory: Int, count: Int)? {
        let start = max(0, data.count - 66_000)
        var index = data.count - 22
        while index >= start {
            if read32(data, index) == 0x06054b50 {
                let count = Int(read16(data, index + 10))
                let directory = Int(read32(data, index + 16))
                return (directory, count)
            }
            index -= 1
        }
        return nil
    }

    private static func read16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(octet(data, offset)) | (UInt16(octet(data, offset + 1)) << 8)
    }

    private static func read32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(octet(data, offset))
            | (UInt32(octet(data, offset + 1)) << 8)
            | (UInt32(octet(data, offset + 2)) << 16)
            | (UInt32(octet(data, offset + 3)) << 24)
    }
}

enum Deflate {
    static func inflate(_ data: Data, size: Int) -> Data? {
        var reader = BitReader(data)
        var output = Data()
        output.reserveCapacity(size)
        var final = false
        while !final {
            final = reader.nextBit() == 1
            switch reader.bits(2) {
            case 0:
                reader.align()
                let length = Int(reader.bits(16))
                let complement = Int(reader.bits(16))
                guard length + complement == 0xFFFF else { return nil }
                guard let chunk = reader.bytes(length) else { return nil }
                output.append(chunk)
            case 1:
                guard expand(reader: &reader, literal: fixedLiteral(), distance: fixedDistance(), into: &output) else { return nil }
            case 2:
                guard let tables = dynamicTables(&reader),
                      expand(reader: &reader, literal: tables.literal, distance: tables.distance, into: &output) else { return nil }
            default:
                return nil
            }
        }
        return output
    }

    private static func expand(reader: inout BitReader, literal: Huffman, distance: Huffman, into output: inout Data) -> Bool {
        let lengths = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
        let extras = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
        let distances = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
        let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
        while true {
            let symbol = literal.decode(&reader)
            if symbol < 256 {
                output.append(UInt8(symbol))
            } else if symbol == 256 {
                return true
            } else if symbol <= 285 {
                let index = symbol - 257
                guard lengths.indices.contains(index) else { return false }
                let length = lengths[index] + Int(reader.bits(extras[index]))
                let distanceSymbol = distance.decode(&reader)
                guard distances.indices.contains(distanceSymbol) else { return false }
                let distance = distances[distanceSymbol] + Int(reader.bits(distanceExtra[distanceSymbol]))
                guard distance > 0, distance <= output.count else { return false }
                for _ in 0..<length {
                    output.append(output[output.count - distance])
                }
            } else {
                return false
            }
        }
    }

    private static func dynamicTables(_ reader: inout BitReader) -> (literal: Huffman, distance: Huffman)? {
        let literalCount = Int(reader.bits(5)) + 257
        let distanceCount = Int(reader.bits(5)) + 1
        let codeCount = Int(reader.bits(4)) + 4
        let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
        var codeLengths = [Int](repeating: 0, count: 19)
        for index in 0..<codeCount {
            codeLengths[order[index]] = Int(reader.bits(3))
        }
        let codeTree = Huffman(lengths: codeLengths)
        var lengths: [Int] = []
        while lengths.count < literalCount + distanceCount {
            let symbol = codeTree.decode(&reader)
            if symbol < 16 {
                lengths.append(symbol)
            } else if symbol == 16, let last = lengths.last {
                for _ in 0..<(3 + Int(reader.bits(2))) { lengths.append(last) }
            } else if symbol == 17 {
                for _ in 0..<(3 + Int(reader.bits(3))) { lengths.append(0) }
            } else if symbol == 18 {
                for _ in 0..<(11 + Int(reader.bits(7))) { lengths.append(0) }
            } else {
                return nil
            }
        }
        return (
            Huffman(lengths: Array(lengths.prefix(literalCount))),
            Huffman(lengths: Array(lengths.dropFirst(literalCount).prefix(distanceCount)))
        )
    }

    private static func fixedLiteral() -> Huffman {
        var lengths = [Int](repeating: 8, count: 144)
        lengths += [Int](repeating: 9, count: 112)
        lengths += [Int](repeating: 7, count: 24)
        lengths += [Int](repeating: 8, count: 8)
        return Huffman(lengths: lengths)
    }

    private static func fixedDistance() -> Huffman {
        Huffman(lengths: [Int](repeating: 5, count: 32))
    }
}

struct BitReader {
    var data: Data
    var index = 0
    var bitOffset = 0

    init(_ data: Data) { self.data = data }

    mutating func nextBit() -> Int { Int(bits(1)) }

    mutating func bits(_ count: Int) -> UInt32 {
        var value: UInt32 = 0
        for shift in 0..<count {
            if bitOffset == 0 {
                guard index < data.count else { return value }
            }
            let byte = UInt32(octet(data, index))
            if (byte >> bitOffset) & 1 == 1 { value |= 1 << shift }
            bitOffset += 1
            if bitOffset == 8 {
                bitOffset = 0
                index += 1
            }
        }
        return value
    }

    mutating func align() {
        if bitOffset != 0 {
            bitOffset = 0
            index += 1
        }
    }

    mutating func bytes(_ count: Int) -> Data? {
        guard index + count <= data.count else { return nil }
        let chunk = data.subdata(in: index..<(index + count))
        index += count
        return chunk
    }
}

struct Huffman {
    var count: [Int]
    var symbol: [Int]

    init(lengths: [Int]) {
        var count = [Int](repeating: 0, count: 16)
        for length in lengths where length > 0 && length < count.count {
            count[length] += 1
        }
        var offsets = [Int](repeating: 0, count: 16)
        for length in 1..<15 {
            offsets[length + 1] = offsets[length] + count[length]
        }
        var symbol = [Int](repeating: 0, count: lengths.count)
        for (value, length) in lengths.enumerated() where length > 0 && length < offsets.count {
            symbol[offsets[length]] = value
            offsets[length] += 1
        }
        self.count = count
        self.symbol = symbol
    }

    func decode(_ reader: inout BitReader) -> Int {
        var code = 0
        var first = 0
        var index = 0
        for length in 1..<count.count {
            code |= reader.nextBit()
            let available = count[length]
            if code - available < first {
                return symbol[index + (code - first)]
            }
            index += available
            first += available
            first <<= 1
            code <<= 1
        }
        return 256
    }
}

enum CompoundFile {
    static func extract(_ data: Data) -> [String: Data]? {
        guard data.count >= 512, data.prefix(8) == Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) else { return nil }
        let sectorShift = Int(read16(data, 0x1E))
        let sectorSize = 1 << sectorShift
        guard sectorSize == 512 || sectorSize == 4096 else { return nil }
        let directoryStart = Int(read32(data, 0x30))
        let fat = fileAllocationTable(data, sectorSize: sectorSize)
        guard !fat.isEmpty else { return nil }
        let cutoff = Int(read32(data, 0x38))
        let miniSize = 1 << Int(read16(data, 0x20))
        let entries = directoryEntries(data, start: directoryStart, fat: fat, sectorSize: sectorSize)
        let root = entries.first { $0.type == 5 }
        let miniStream = root.flatMap {
            stream(data, start: $0.start, size: $0.size, fat: fat, sectorSize: sectorSize)
        } ?? Data()
        let miniFAT = miniAllocationTable(data, fat: fat, sectorSize: sectorSize)
        var files: [String: Data] = [:]
        for entry in entries where entry.type == 2 && !entry.name.isEmpty {
            let bytes: Data?
            if entry.size > 0, entry.size < cutoff {
                bytes = miniStreamBytes(miniStream, start: entry.start, size: entry.size, fat: miniFAT, sectorSize: miniSize)
            } else {
                bytes = stream(data, start: entry.start, size: entry.size, fat: fat, sectorSize: sectorSize)
            }
            if let bytes { files[entry.name] = bytes }
        }
        return files.isEmpty ? nil : files
    }

    private struct DirectoryEntry {
        var name: String
        var type: UInt8
        var start: Int
        var size: Int
    }

    private static func directoryEntries(_ data: Data, start: Int, fat: [Int], sectorSize: Int) -> [DirectoryEntry] {
        var entries: [DirectoryEntry] = []
        var sector = start
        var seen = 0
        while sector >= 0, sector < fat.count, seen < 10_000 {
            let entry = headerSize(sectorSize) + sector * sectorSize
            guard entry + sectorSize <= data.count else { break }
            for index in 0..<(sectorSize / 128) {
                let base = entry + index * 128
                guard base + 128 <= data.count else { continue }
                let nameLength = Int(read16(data, base + 64))
                guard nameLength >= 4 else { continue }
                let nameBytes = data.subdata(in: base..<(base + min(nameLength - 2, 64)))
                let name = String(data: nameBytes, encoding: .utf16LittleEndian) ?? ""
                entries.append(DirectoryEntry(
                    name: name,
                    type: octet(data, base + 66),
                    start: Int(read32(data, base + 116)),
                    size: Int(read32(data, base + 120))
                ))
            }
            let next = fat[sector]
            if next < 0 || next >= 0xFFFFFFFA { break }
            sector = next
            seen += 1
        }
        return entries
    }

    private static func miniAllocationTable(_ data: Data, fat: [Int], sectorSize: Int) -> [Int] {
        var sector = Int(read32(data, 0x3C))
        var table: [Int] = []
        var seen = 0
        while sector >= 0, sector < fat.count, seen < 10_000 {
            let start = headerSize(sectorSize) + sector * sectorSize
            guard start + sectorSize <= data.count else { break }
            for offset in stride(from: 0, to: sectorSize, by: 4) {
                table.append(Int(read32(data, start + offset)))
            }
            let next = fat[sector]
            if next < 0 || next >= 0xFFFFFFFA { break }
            sector = next
            seen += 1
        }
        return table
    }

    private static func miniStreamBytes(_ data: Data, start: Int, size: Int, fat: [Int], sectorSize: Int) -> Data? {
        guard size > 0, sectorSize > 0, start >= 0 else { return Data() }
        var output = Data()
        var sector = start
        var seen = 0
        while sector >= 0, sector < fat.count, output.count < size, seen < 100_000 {
            let startByte = sector * sectorSize
            guard startByte < data.count else { return nil }
            let end = min(startByte + sectorSize, data.count, startByte + (size - output.count))
            output.append(data.subdata(in: startByte..<end))
            let next = fat[sector]
            if next < 0 || next >= 0xFFFFFFFA { break }
            sector = next
            seen += 1
        }
        return Data(output.prefix(size))
    }

    private static func fileAllocationTable(_ data: Data, sectorSize: Int) -> [Int] {
        let difatCount = min(109, (data.count - 0x4C) / 4)
        var sectors: [Int] = []
        for index in 0..<difatCount {
            let sector = Int(read32(data, 0x4C + index * 4))
            if sector > 0xFFFFFFFA { break }
            sectors.append(sector)
        }
        var fat: [Int] = []
        for sector in sectors {
            let start = headerSize(sectorSize) + sector * sectorSize
            guard start + sectorSize <= data.count else { continue }
            for offset in stride(from: 0, to: sectorSize, by: 4) {
                fat.append(Int(read32(data, start + offset)))
            }
        }
        return fat
    }

    private static func stream(_ data: Data, start: Int, size: Int, fat: [Int], sectorSize: Int) -> Data? {
        guard size > 0, start >= 0 else { return Data() }
        var output = Data()
        var sector = start
        var seen = 0
        while sector >= 0, sector < fat.count, output.count < size, seen < 100_000 {
            let startByte = headerSize(sectorSize) + sector * sectorSize
            guard startByte + sectorSize <= data.count else { return nil }
            output.append(data.subdata(in: startByte..<min(startByte + sectorSize, startByte + (size - output.count))))
            let next = fat[sector]
            if next >= 0xFFFFFFFA { break }
            sector = next
            seen += 1
        }
        return output.prefix(size) == output ? output : Data(output.prefix(size))
    }

    private static func headerSize(_ sectorSize: Int) -> Int { sectorSize }

    private static func read16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(octet(data, offset)) | (UInt16(octet(data, offset + 1)) << 8)
    }

    private static func read32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(octet(data, offset))
            | (UInt32(octet(data, offset + 1)) << 8)
            | (UInt32(octet(data, offset + 2)) << 16)
            | (UInt32(octet(data, offset + 3)) << 24)
    }
}

enum OfficeEncryption {
    static func decrypt(info: Data, package: Data, password: String) -> Data? {
        guard let xmlRange = info.range(of: Data("<encryption".utf8)) else { return nil }
        guard let xml = String(data: info.subdata(in: xmlRange.lowerBound..<info.endIndex), encoding: .utf8),
              let key = encryptedKey(xml),
              let keyData = keyDataSalt(xml) else { return nil }
        guard let derived = secretKey(key, password: password) else { return nil }
        return decryptPackage(package, key: derived, salt: keyData.salt, hash: keyData.hash)
    }

    private struct KeyInfo {
        var spin: Int
        var hash: String
        var keyBits: Int
        var salt: Data
        var verifierInput: Data
        var verifierHash: Data
        var encryptedKey: Data
    }

    private static func encryptedKey(_ xml: String) -> KeyInfo? {
        guard let spin = intAttribute("spinCount", xml),
              let keyBits = intAttribute("keyBits", xml),
              let salt = dataAttribute("saltValue", xml),
              let input = dataAttribute("encryptedVerifierHashInput", xml),
              let hash = dataAttribute("encryptedVerifierHashValue", xml),
              let key = dataAttribute("encryptedKeyValue", xml) else { return nil }
        let algorithm = stringAttribute("hashAlgorithm", xml) ?? "SHA512"
        return KeyInfo(spin: spin, hash: algorithm, keyBits: keyBits, salt: salt, verifierInput: input, verifierHash: hash, encryptedKey: key)
    }

    private static func keyDataSalt(_ xml: String) -> (salt: Data, hash: String)? {
        guard let element = xml.range(of: "<keyData") else { return nil }
        let slice = String(xml[element.lowerBound...])
        guard let salt = dataAttribute("saltValue", slice) else { return nil }
        return (salt, stringAttribute("hashAlgorithm", slice) ?? "SHA512")
    }

    private static func secretKey(_ info: KeyInfo, password: String) -> Data? {
        let passwordHash = iteratedHash(password: password, salt: info.salt, spin: info.spin, algorithm: info.hash)
        let verifierKey = key(passwordHash, block: Data([0xFE, 0xA7, 0xD2, 0x76, 0x3B, 0x4B, 0x9E, 0x79]), algorithm: info.hash, bits: info.keyBits)
        let iv = initializationVector(salt: info.salt, block: Data([0xFE, 0xA7, 0xD2, 0x76, 0x3B, 0x4B, 0x9E, 0x79]), algorithm: info.hash)
        guard let decryptedInput = aesDecrypt(info.verifierInput, key: verifierKey, iv: iv),
              let decryptedHash = aesDecrypt(info.verifierHash, key: verifierKey, iv: iv) else { return nil }
        let check = digest(decryptedInput, algorithm: info.hash)
        guard decryptedHash.prefix(check.count) == check else { return nil }
        let packageKey = key(passwordHash, block: Data([0x14, 0x6E, 0x0B, 0xE7, 0xAB, 0xAC, 0xD0, 0xD6]), algorithm: info.hash, bits: info.keyBits)
        let keyIV = initializationVector(salt: info.salt, block: Data([0x14, 0x6E, 0x0B, 0xE7, 0xAB, 0xAC, 0xD0, 0xD6]), algorithm: info.hash)
        return aesDecrypt(info.encryptedKey, key: packageKey, iv: keyIV)?.prefix(info.keyBits / 8)
    }

    private static func decryptPackage(_ package: Data, key: Data, salt: Data, hash: String) -> Data? {
        guard package.count > 8 else { return nil }
        let encrypted = package.subdata(in: 8..<package.count)
        var plain = Data()
        var offset = 0
        var segment = 0
        while offset < encrypted.count {
            let end = min(offset + 4096, encrypted.count)
            var block = Data(count: 4)
            block[0] = UInt8(segment & 0xFF)
            block[1] = UInt8((segment >> 8) & 0xFF)
            block[2] = UInt8((segment >> 16) & 0xFF)
            block[3] = UInt8((segment >> 24) & 0xFF)
            let iv = initializationVector(salt: salt, block: block, algorithm: hash)
            guard let chunk = aesDecrypt(encrypted.subdata(in: offset..<end), key: key, iv: iv) else { return nil }
            plain.append(chunk)
            offset = end
            segment += 1
        }
        return plain
    }

    static func iteratedHash(password: String, salt: Data, spin: Int, algorithm: String) -> Data {
        var value = digest(salt + password.utf16LE, algorithm: algorithm)
        for index in 0..<spin {
            var counter = Data(count: 4)
            counter[0] = UInt8(index & 0xFF)
            counter[1] = UInt8((index >> 8) & 0xFF)
            counter[2] = UInt8((index >> 16) & 0xFF)
            counter[3] = UInt8((index >> 24) & 0xFF)
            value = digest(counter + value, algorithm: algorithm)
        }
        return value
    }

    private static func key(_ hash: Data, block: Data, algorithm: String, bits: Int) -> Data {
        Data(digest(hash + block, algorithm: algorithm).prefix(bits / 8))
    }

    private static func initializationVector(salt: Data, block: Data?, algorithm: String) -> Data {
        let raw = block.map { digest(salt + $0, algorithm: algorithm) } ?? salt
        if raw.count >= 16 { return raw.prefix(16) }
        return raw + Data(repeating: 0, count: 16 - raw.count)
    }

    private static func digest(_ data: Data, algorithm: String) -> Data {
        if algorithm.uppercased().contains("SHA1") {
            let digest = Insecure.SHA1.hash(data: data)
            return Data(digest)
        }
        return Data(SHA512.hash(data: data))
    }

    private static func aesDecrypt(_ data: Data, key: Data, iv: Data) -> Data? {
        guard key.count == kCCKeySizeAES128 || key.count == kCCKeySizeAES256 else { return nil }
        var output = Data(count: data.count + kCCBlockSizeAES128)
        var written = 0
        let capacity = output.count
        let status = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress,
                            input.baseAddress, data.count,
                            out.baseAddress, capacity,
                            &written
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return output.prefix(written)
    }

    private static func intAttribute(_ name: String, _ xml: String) -> Int? {
        guard let value = stringAttribute(name, xml) else { return nil }
        return Int(value)
    }

    private static func dataAttribute(_ name: String, _ xml: String) -> Data? {
        guard let value = stringAttribute(name, xml) else { return nil }
        return Data(base64Encoded: value)
    }

    private static func stringAttribute(_ name: String, _ xml: String) -> String? {
        guard let range = xml.range(of: "\(name)=\"") else { return nil }
        let rest = xml[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }
}

private extension String {
    var utf16LE: Data {
        Data(utf16.flatMap { [UInt8($0 & 0xFF), UInt8(($0 >> 8) & 0xFF)] })
    }
}

private func octet(_ data: Data, _ offset: Int) -> UInt8 {
    data[data.index(data.startIndex, offsetBy: offset)]
}
