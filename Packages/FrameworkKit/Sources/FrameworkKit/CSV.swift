import Foundation

/// RFC 4180 CSV writing, with protection against spreadsheet formula injection.
public enum CSV {
    /// Characters that make spreadsheets treat a cell as a formula when they start it.
    static let formulaStarters: Set<Character> = ["=", "+", "@", "\t", "\r"]

    /// Quotes a field when needed and neutralizes values that a spreadsheet would run as a formula
    /// (OWASP "CSV injection") by prefixing an apostrophe.
    public static func field(_ value: String) -> String {
        var v = value
        if let first = v.first {
            let second = v.dropFirst().first
            let startsFormula = formulaStarters.contains(first)
                || (first == "-" && second.map { !$0.isWhitespace } == true)
            if startsFormula { v = "'" + v }
        }
        let needsQuotes = v.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
            || v.first == " " || v.last == " "
        guard needsQuotes else { return v }
        return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    public static func line(_ fields: [String]) -> String {
        fields.map(field).joined(separator: ",")
    }

    /// A complete document with CRLF line endings.
    public static func document(header: [String], rows: [[String]]) -> String {
        ([line(header)] + rows.map(line)).joined(separator: "\r\n") + "\r\n"
    }

    /// UTF-8 with a byte-order mark so spreadsheet apps detect the encoding.
    public static func data(header: [String], rows: [[String]]) -> Data {
        Data([0xEF, 0xBB, 0xBF]) + Data(document(header: header, rows: rows).utf8)
    }
}
