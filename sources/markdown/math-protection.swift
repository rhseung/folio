// 마크다운 이스케이프는 TeX을 망가뜨리므로(`\{`가 `{`가 되고 `a_1_b`가 강조가 된다) 파싱 전에 수식을 코드로 감싼다.
// `[[...]]` 안의 `|`도 이스케이프한다. 표의 행에서 GFM이 그 자리에서 칸을 나누고 머리 폭을 넘는 칸을 버리기
// 때문이다. GFM은 칸 안과 다른 곳의 `\|`를 되돌리므로 렌더러는 여전히 `[[target|alias]]`를 읽는다.
// 표의 행에서는 수식 안의 `|`도 이스케이프한다. 코드 span은 표 밖에서 `\|`를 그대로 두므로 표 밖의 수식은 건드리지 않는다.
public enum MathProtection {
    // `math`는 쓴 사람이 고른 펜스라 노트 문법과 상관없이 TeX이고, `$$` 블록은 노트 문법을 따른다. 사용 영역 문자로 둘을
    // 구분한다.
    public static let blockLanguage = "\u{E000}math"
    public static let marker: Character = "\u{E000}"

    static func protect(_ text: String) -> String { protectMapped(text).text }

    static func protectMapped(_ text: String) -> (text: String, origin: [Int]) {
        var out: [String] = []
        var origin: [Int] = []
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)[...]
        var fence: String?
        var table = false
        var tableDepth = 0
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
                table = false
                fence = String(trimmed.prefix(3))
                out.append(line)
                continue
            }
            let prefix = String(line.prefix { $0 == " " || $0 == ">" })
            if line.dropFirst(prefix.count).hasPrefix("$$") {
                table = false
                var body = String(line.dropFirst(prefix.count + 2)).trimmingCharacters(in: .whitespaces)
                while !body.hasSuffix("$$"), let next = lines.popFirst() {
                    body += "\n" + String(next.dropFirst(min(prefix.count, next.prefix { $0 == " " || $0 == ">" }.count)))
                }
                if body.hasSuffix("$$") { body.removeLast(2) }
                out.append(prefix + "```" + blockLanguage)
                out += body.trimmingCharacters(in: .newlines).split(separator: "\n", omittingEmptySubsequences: false).map { prefix + $0 }
                while origin.count < out.count { origin.append(n) }
                out.append(prefix + "```")
                origin.append(lines.startIndex)
                continue
            }
            // 머리 행은 구분 행으로 알아본다. 파싱한 표로 고르면 머리 행의 수식 `|`가 칸 수를 늘려 표가 되지 않는다.
            // GFM은 빈 줄 말고도 인용 깊이가 바뀌거나 다른 블록이 시작되는 줄에서 표를 끝낸다.
            let content = line.dropFirst(prefix.count)
            let depth = prefix.count { $0 == ">" }
            if content.allSatisfy(\.isWhitespace) || depth != tableDepth || startsBlock(content) { table = false }
            if !table, content.contains("|"), let next = lines.first, isDelimiterRow(next) {
                table = true
                tableDepth = depth
            }
            out.append(protectInline(line, table: table))
        }
        return (out.joined(separator: "\n"), origin)
    }

    public static func protectInline(_ line: String, table: Bool = false) -> String {
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
                // TeX의 `\|`도 `\\|`가 되어 GFM이 `\|`로 되돌린다.
                let tex = table ? close.replacing("|", with: "\\|") : close
                result += ticks + String(marker) + tex + ticks
                chars = Array(rest.dropFirst(close.count + 1))[...]
            default:
                result.append(c)
            }
        }
        return result
    }

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

    static func isDelimiterRow(_ line: String) -> Bool {
        let row = line.drop { $0 == " " || $0 == ">" }.trimmingCharacters(in: .whitespaces)
        return row.contains("|") && row.wholeMatch(of: /\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?/) != nil
    }

    static func startsBlock(_ content: Substring) -> Bool {
        content.prefixMatch(of: /#{1,6}(\s|$)|[-*+](\s|$)|\d{1,9}[.)](\s|$)|<|([-*_])\s*(\1\s*){2,}$/) != nil
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
