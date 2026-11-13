// 마크다운 이스케이프는 TeX을 망가뜨리므로(`\{`가 `{`가 되고 `a_1_b`가 강조가 된다) 파싱 전에 수식을 코드로 감싼다.
// `[[...]]` 안의 `|`도 이스케이프한다. 표의 행에서 GFM이 그 자리에서 칸을 나누고 머리 폭을 넘는 칸을 버리기
// 때문이다. GFM은 칸 안과 다른 곳의 `\|`를 되돌리므로 렌더러는 여전히 `[[target|alias]]`를 읽는다.
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

public enum MathFence {
    public enum Syntax: String, Sendable, CaseIterable {
        case latex, asciimath
    }

    public static let languages: [(name: String, syntax: Syntax)] = [
        ("math", .latex), ("tex", .latex), ("latex", .latex), ("asciimath", .asciimath), ("am", .asciimath),
    ]

    public static func syntax(_ info: String?) -> Syntax? {
        guard let word = info?.split(whereSeparator: \.isWhitespace).first?.lowercased() else { return nil }
        return languages.first { $0.name == word }?.syntax
    }
}
