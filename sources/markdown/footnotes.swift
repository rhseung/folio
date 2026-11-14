import Foundation
import Markdown

// swift-markdown 0.9는 cmark-gfm의 각주 확장을 켜지 않으므로 각주를 여기서 읽는다. 그대로 두면 `[^1]: https://`는
// CommonMark 링크 정의가 되어 사라지고, 모든 `[^1]`이 그 정의로 가는 링크가 된다. 그래서 파싱 전에 정의의 `[`를
// `marker`로 바꾼다. 두 글자는 UTF-16 길이가 같으므로 오프셋이 원문과 맞는다.
public enum Footnotes {
    public static let marker: Character = "\u{E001}"

    static var definitionLine: Regex<(Substring, Substring)> { #/^ {0,3}\[\^([^\]\s]+)\]:/# }
    static var reference: Regex<(Substring, Substring)> { #/\[\^([^\]\s]+)\]/# }
    static var maskedStart: Regex<(Substring, Substring)> { #/^\x{E001}\^([^\]\s]+)\]:[ \t]*/# }

    static func key(_ label: some StringProtocol) -> String { label.lowercased() }

    public static func mask(_ text: String) -> String {
        let out = NSMutableString(string: text)
        for line in lines(text) where line.definition != nil {
            out.replaceCharacters(in: NSRange(location: line.bracket, length: 1), with: String(marker))
        }
        return out as String
    }

    public struct Mark: Equatable, Sendable {
        public var range: NSRange
        public var label: NSRange
        public var definition: Bool
    }

    public static func marks(in text: String) -> [Mark] {
        var out: [Mark] = []
        for line in lines(text) {
            var skip = 0
            if let label = line.definition {
                let length = label.length + 4
                out.append(Mark(range: NSRange(location: line.bracket, length: length), label: label, definition: true))
                skip = line.bracket - line.range.location + length
            }
            let s = line.text
            for m in s.matches(of: reference) {
                let r = NSRange(m.range, in: s)
                guard r.location >= skip else { continue }
                let label = NSRange(m.1.startIndex..<m.1.endIndex, in: s)
                out.append(
                    Mark(
                        range: NSRange(location: line.range.location + r.location, length: r.length),
                        label: NSRange(location: line.range.location + label.location, length: label.length), definition: false))
            }
        }
        return out
    }

    struct Line {
        var range: NSRange
        var text: String
        var definition: NSRange?
        var bracket: Int
    }

    static func lines(_ text: String) -> [Line] {
        var out: [Line] = []
        var fence: String?
        var at = 0
        for sub in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(sub)
            let length = line.utf16.count
            defer { at += length + 1 }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if trimmed.hasPrefix(open) { fence = nil }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                continue
            }
            var entry = Line(range: NSRange(location: at, length: length), text: line, definition: nil, bracket: at)
            if let m = line.prefixMatch(of: definitionLine) {
                let label = NSRange(m.1.startIndex..<m.1.endIndex, in: line)
                entry.definition = NSRange(location: at + label.location, length: label.length)
                entry.bracket = at + label.location - 2
            }
            out.append(entry)
        }
        return out
    }
}
