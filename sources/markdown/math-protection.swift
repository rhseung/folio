/// Markdown escapes would eat TeX (`\{` becomes `{`, `a_1_b` turns into emphasis), so math is wrapped
/// in code before parsing: `$$...$$` becomes a fenced block in `blockLanguage` and `$...$` an inline code span
/// starting with `mathMarker`. Code spans and fenced code are left alone, and `\$` is a literal dollar.
/// A `|` inside `[[…]]` is escaped too: in a table row GFM would split the cell there and drop the cells past the
/// header's width, as `[[note:<ID>|title]]` always has one. GFM unescapes `\|` in a cell and markdown elsewhere, so
/// the renderer still reads `[[target|alias]]`.
public enum MathProtection {
    /// Not `math`: that is a fence the writer chose, which is TeX whatever the note's syntax (`MathFence`), while a
    /// `$$` block is in the note's syntax. The private-use character keeps the two apart.
    public static let blockLanguage = "\u{E000}math"
    /// Private-use character marking an inline code span that holds math.
    public static let marker: Character = "\u{E000}"

    static func protect(_ text: String) -> String { protectMapped(text).text }

    /// Also the original line each protected line came from (1-based), since a one-line `$$…$$` becomes three.
    static func protectMapped(_ text: String) -> (text: String, origin: [Int]) {
        var out: [String] = []
        var origin: [Int] = []
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)[...]
        var fence: String?
        while let line = lines.popFirst() {
            let n = lines.startIndex
            defer { while origin.count < out.count { origin.append(n) } }
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
            // Keep the quote/indent prefix so display math stays inside its container.
            let prefix = String(line.prefix { $0 == " " || $0 == ">" })
            if line.dropFirst(prefix.count).hasPrefix("$$") {
                var body = String(line.dropFirst(prefix.count + 2)).trimmingCharacters(in: .whitespaces)
                while !body.hasSuffix("$$"), let next = lines.popFirst() {
                    body += "\n" + String(next.dropFirst(min(prefix.count, next.prefix { $0 == " " || $0 == ">" }.count)))
                }
                if body.hasSuffix("$$") { body.removeLast(2) }
                out.append(prefix + "```" + blockLanguage)
                out += body.trimmingCharacters(in: .newlines).split(separator: "\n", omittingEmptySubsequences: false).map { prefix + $0 }
                while origin.count < out.count { origin.append(n) }
                // The closing fence stands for the line the `$$` closed on, so the block ends where its source does.
                out.append(prefix + "```")
                origin.append(lines.startIndex)
                continue
            }
            out.append(protectInline(line))
        }
        return (out.joined(separator: "\n"), origin)
    }

    public static func protectInline(_ line: String) -> String {
        var result = ""
        var chars = Array(line)[...]
        while let c = chars.popFirst() {
            switch c {
            case "\\" where chars.first == "$":
                result.append("\\$")
                chars.removeFirst()
            case "`":
                var ticks = "`"
                while chars.first == "`" { ticks.append(chars.removeFirst()) }
                result += ticks
                let rest = String(chars)
                if let close = rest.range(of: ticks) {
                    result += rest[..<close.upperBound]
                    chars = Array(rest[close.upperBound...])[...]
                }
            case "[" where chars.first == "[":
                let rest = String(chars.dropFirst())
                guard let close = rest.range(of: "]]"), !rest[..<close.lowerBound].contains("]") else {
                    result.append(c)
                    continue
                }
                let inner = rest[..<close.lowerBound]
                result += "[[" + escapePipes(inner) + "]]"
                chars = Array(rest[close.upperBound...])[...]
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

    /// Pipes escaped, as a GFM cell needs them; ones already escaped stay as they are.
    static func escapePipes(_ text: some StringProtocol) -> String {
        var out = ""
        var escaped = false
        for ch in text {
            if ch == "|", !escaped { out.append("\\") }
            out.append(ch)
            escaped = ch == "\\" && !escaped
        }
        return out
    }

    static func closingDollar(in s: String) -> String? {
        var previous: Character?
        for (i, c) in s.enumerated() {
            if c == "$", previous != "\\" { return String(s.prefix(i)) }
            previous = c
        }
        return nil
    }
}

/// A fenced block written as a formula in a syntax of its own, so one block of an AsciiMath note can be TeX (which has
/// `\begin{align}` and the other environments AsciiMath lacks) without the whole note changing. `$…$` and `$$…$$` stay
/// in the note's syntax.
public enum MathFence {
    /// The same raw values as the note's `math` frontmatter, so the app reads them as its own syntax.
    public enum Syntax: String, Sendable, CaseIterable {
        case latex, asciimath
    }

    /// The fence names, in the order the language menu offers them.
    public static let languages: [(name: String, syntax: Syntax)] = [
        ("math", .latex), ("tex", .latex), ("latex", .latex), ("asciimath", .asciimath), ("am", .asciimath),
    ]

    /// The syntax a fence's info string (or just its language) names, or nil for a code block.
    public static func syntax(_ info: String?) -> Syntax? {
        guard let word = info?.split(whereSeparator: \.isWhitespace).first?.lowercased() else { return nil }
        return languages.first { $0.name == word }?.syntax
    }
}
