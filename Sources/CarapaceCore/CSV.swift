import Foundation
import CoreFoundation

public struct CSVTable: Sendable {
    public var headers: [String]
    public var rows: [[String]]

    public init(headers: [String], rows: [[String]]) {
        self.headers = headers
        self.rows = rows
    }
}

public enum CSVParser {
    public static func decode(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) {
            return text.replacingOccurrences(of: "\u{FEFF}", with: "")
        }
        let gbk = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        if let text = String(data: data, encoding: gbk) {
            return text.replacingOccurrences(of: "\u{FEFF}", with: "")
        }
        return nil
    }

    public static func parse(_ text: String) -> CSVTable {
        let delimiter = detectDelimiter(text)
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var quoted = false
        var index = text.startIndex

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            if !row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                rows.append(row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            }
            row = []
        }

        while index < text.endIndex {
            let ch = text[index]
            if quoted {
                if ch == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(ch)
                }
            } else {
                switch ch {
                case "\"":
                    if field.isEmpty { quoted = true } else { field.append(ch) }
                case delimiter:
                    endField()
                case "\r":
                    if text.index(after: index) < text.endIndex,
                       text[text.index(after: index)] == "\n" {
                        index = text.index(after: index)
                    }
                    endRow()
                case "\n":
                    endRow()
                default:
                    field.append(ch)
                }
            }
            index = text.index(after: index)
        }
        if !field.isEmpty || !row.isEmpty { endRow() }

        guard let first = rows.first else { return CSVTable(headers: [], rows: []) }
        let headers = first.enumerated().map { i, value in
            value.isEmpty ? "col_\(i + 1)" : value
        }
        return CSVTable(headers: headers, rows: Array(rows.dropFirst()))
    }

    private static func detectDelimiter(_ text: String) -> Character {
        let sample = text.prefix(4000)
        let counts: [(Character, Int)] = [(",", sample.filter { $0 == "," }.count),
                                          ("\t", sample.filter { $0 == "\t" }.count),
                                          (";", sample.filter { $0 == ";" }.count)]
        return counts.max { $0.1 < $1.1 }?.0 ?? ","
    }
}
