import Foundation

// 카드와 문제의 짧은 글에서 수식을 떼어 낸다. 글 전체를 노트 렌더러로 그리지 않고 수식만 그림으로 바꿔 글 사이에 넣는다.
// `\$`는 수식이 아닌 달러 기호이고, 닫히지 않은 `$`는 글로 둔다.
public enum MathSpans {
    public enum Span: Equatable, Sendable {
        case text(String)
        case inline(String)
        case display(String)
    }

    public static func split(_ text: String) -> [Span] {
        var out: [Span] = []
        var plain = ""
        var rest = Substring(text)
        func flush() {
            if !plain.isEmpty { out.append(.text(plain)) }
            plain = ""
        }
        while let c = rest.first {
            if c == "\\", rest.dropFirst().first == "$" {
                plain.append("$")
                rest = rest.dropFirst(2)
                continue
            }
            guard c == "$" else {
                plain.append(c)
                rest = rest.dropFirst()
                continue
            }
            let display = rest.hasPrefix("$$")
            let fence = display ? "$$" : "$"
            let inside = rest.dropFirst(fence.count)
            guard let close = closing(fence, in: inside), !inside[..<close].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                plain.append(contentsOf: fence)
                rest = inside
                continue
            }
            flush()
            let formula = String(inside[..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(display ? .display(formula) : .inline(formula))
            rest = inside[close...].dropFirst(fence.count)
        }
        flush()
        return out
    }

    public static func hasMath(_ text: String) -> Bool { split(text).contains { if case .text = $0 { false } else { true } } }

    private static func closing(_ fence: String, in text: Substring) -> Substring.Index? {
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "\\" {
                i = text.index(i, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                continue
            }
            if text[i...].hasPrefix(fence) { return i }
            // 줄 안 수식은 줄을 넘지 않는다. 넘으면 달러 기호를 쓴 글이다.
            if fence == "$", text[i] == "\n" { return nil }
            i = text.index(after: i)
        }
        return nil
    }
}
