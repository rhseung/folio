/// Markdown escapes would eat TeX (`\{` becomes `{`, `a_1_b` turns into emphasis), so math is wrapped
/// in code before parsing: `$$...$$` becomes a ```` ```math ```` block and `$...$` an inline code span
/// starting with `mathMarker`. Code spans and fenced code are left alone, and `\$` is a literal dollar.
enum MathProtection {
    static let blockLanguage = "math"
    /// Private-use character marking an inline code span that holds math.
    static let marker: Character = "\u{E000}"

    static func protect(_ text: String) -> String {
        var out: [String] = []
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)[...]
        var fence: String?
        while let line = lines.popFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                out.append(line)
                if trimmed.hasPrefix(open) { fence = nil }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                out.append(line)
                continue
            }
            // Display math, possibly spanning lines; keep the quote/indent prefix so it stays inside its container.
            let prefix = String(line.prefix { $0 == " " || $0 == ">" })
            if line.dropFirst(prefix.count).hasPrefix("$$") {
                var body = String(line.dropFirst(prefix.count + 2)).trimmingCharacters(in: .whitespaces)
                while !body.hasSuffix("$$"), let next = lines.popFirst() {
                    body += "\n" + String(next.dropFirst(min(prefix.count, next.prefix { $0 == " " || $0 == ">" }.count)))
                }
                if body.hasSuffix("$$") { body.removeLast(2) }
                out.append(prefix + "```" + blockLanguage)
                out += body.trimmingCharacters(in: .newlines).split(separator: "\n", omittingEmptySubsequences: false).map { prefix + $0 }
                out.append(prefix + "```")
                continue
            }
            out.append(protectInline(line))
        }
        return out.joined(separator: "\n")
    }

    static func protectInline(_ line: String) -> String {
        var result = ""
        var chars = Array(line)[...]
        while let c = chars.popFirst() {
            switch c {
            case "\\" where chars.first == "$":
                result.append("\\$")
                chars.removeFirst()
            case "`":
                // Copy a code span through unchanged.
                var ticks = "`"
                while chars.first == "`" { ticks.append(chars.removeFirst()) }
                result += ticks
                let rest = String(chars)
                if let close = rest.range(of: ticks) {
                    result += rest[..<close.upperBound]
                    chars = Array(rest[close.upperBound...])[...]
                }
            case "$":
                let rest = String(chars)
                guard let close = closingDollar(in: rest), !close.isEmpty, !close.hasPrefix(" "), !close.hasSuffix(" ") else {
                    result.append(c)
                    continue
                }
                let ticks = close.contains("`") ? "``" : "`"
                result += ticks + String(marker) + close + ticks
                chars = Array(rest.dropFirst(close.count + 1))[...]
            default:
                result.append(c)
            }
        }
        return result
    }

    /// Text up to the next unescaped `$`, or nil if the line has none.
    static func closingDollar(in s: String) -> String? {
        var previous: Character?
        for (i, c) in s.enumerated() {
            if c == "$", previous != "\\" { return String(s.prefix(i)) }
            previous = c
        }
        return nil
    }
}
