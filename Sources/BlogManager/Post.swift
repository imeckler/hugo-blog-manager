import Foundation

struct Post: Identifiable, Hashable {
    /// URL of the markdown file itself (index.md for page bundles, or the .md/.markdown file).
    let id: URL
    var url: URL { id }
    let title: String
    let date: Date?
    let author: String?
    let rawDate: String?

    /// For page bundles this is the bundle directory; for flat posts it's the file.
    /// Used as the user-facing "post" when revealing in Finder.
    let bundleURL: URL

    var filename: String { bundleURL.lastPathComponent }
}

enum Frontmatter {
    /// Parses Hugo frontmatter at the top of a file. Supports TOML (`+++` fences,
    /// `key = value`) and YAML (`---` fences, `key: value`). Returns the
    /// key/value pairs found; values have surrounding quotes stripped.
    static func parse(_ content: String) -> [String: String] {
        let lines = content.components(separatedBy: "\n")
        guard let first = lines.first?.trimmingCharacters(in: .whitespaces) else { return [:] }

        let separator: Character
        switch first {
        case "+++": separator = "="
        case "---": separator = ":"
        default: return [:]
        }
        let fence = first

        var result: [String: String] = [:]
        for i in 1..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed == fence { break }
            guard let sepIndex = trimmed.firstIndex(of: separator) else { continue }
            let key = trimmed[..<sepIndex].trimmingCharacters(in: .whitespaces)
            var value = trimmed[trimmed.index(after: sepIndex)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty {
                result[key] = String(value)
            }
        }
        return result
    }

    static func parseDate(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso2.date(from: raw) { return d }

        let formatters: [DateFormatter] = [
            makeFormatter("yyyy-MM-dd'T'HH:mm:ssXXXXX"),
            makeFormatter("yyyy-MM-dd'T'HH:mm:ssZ"),
            makeFormatter("yyyy-MM-dd'T'HH:mm:ss"),
            makeFormatter("yyyy-MM-dd HH:mm:ss"),
            makeFormatter("yyyy-MM-dd")
        ]
        for f in formatters {
            if let d = f.date(from: raw) { return d }
        }
        return nil
    }

    private static func makeFormatter(_ fmt: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = fmt
        return f
    }
}
