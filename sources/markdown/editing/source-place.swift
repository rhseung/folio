import Foundation

public enum SourcePlace: Equatable, Sendable {
    case text
    case code(language: String)
    case inlineCode
    case math(display: Bool, content: NSRange, fence: MathFence.Syntax? = nil)

    public var isMath: Bool { if case .math = self { true } else { false } }
    public var fence: MathFence.Syntax? { if case .math(_, _, let fence) = self { fence } else { nil } }
    public var isCode: Bool {
        switch self {
        case .code, .inlineCode: true
        default: false
        }
    }

    // 펜스와 `$$` 블록은 `MathScan`과 마크다운 파서가 읽는 방식대로 읽는다. 펜스는 백틱이나 물결표 셋 이상이고, 같은
    // 글자가 그만큼 이상 이어진 줄이 닫는다. `$$` 줄이 연 블록은 `$$`로 끝나는 첫 줄이 닫는다.
    public static func at(_ caret: Int, in text: NSString) -> SourcePlace {
        let caret = min(max(0, caret), text.length)
        var fence: Fence?
        var fenceBody = 0
        var mathStart: Int?
        var at = 0

        while true {
            let line = text.lineRange(for: NSRange(location: at, length: 0))
            let content = SourceLines.content(line, in: text)
            let s = text.substring(with: content)
            let here = caret >= content.location && caret <= NSMaxRange(content)
            if let open = fence {
                let closes = Fence(s).map { $0.closes(open) } ?? false
                if here {
                    guard !closes, let syntax = MathFence.syntax(open.info) else { return .code(language: open.info) }
                    let end = SourceLines.fenceEnd(text, after: line, open: open)
                    return .math(display: true, content: NSRange(location: fenceBody, length: end - fenceBody), fence: syntax)
                }
                if closes { fence = nil }
            } else if let start = mathStart {
                let closes = s.trimmingCharacters(in: .whitespaces).hasSuffix("$$")
                if here {
                    let end =
                        closes
                        ? content.location + (s as NSString).range(of: "$$", options: .backwards).location
                        : SourceLines.blockEnd(text, after: line)
                    if caret > end { return .text }
                    return .math(display: true, content: NSRange(location: start, length: max(0, end - start)))
                }
                if closes { mathStart = nil }
            } else if let open = Fence(s) {
                if here { return .text }
                fence = open
                fenceBody = NSMaxRange(line)
            } else if let opener = SourceLines.displayOpener(s) {
                let bodyStart = content.location + opener
                let rest = (s as NSString).substring(from: opener).trimmingCharacters(in: .whitespaces)
                let closed = rest.hasSuffix("$$")
                if here {
                    guard caret >= bodyStart else { return inline(s, from: content.location, caret: caret) }
                    guard closed else {
                        return .math(
                            display: true,
                            content: NSRange(location: bodyStart, length: SourceLines.blockEnd(text, after: line) - bodyStart))
                    }
                    let end = content.location + (s as NSString).range(of: "$$", options: .backwards).location
                    return caret <= end ? .math(display: true, content: NSRange(location: bodyStart, length: end - bodyStart)) : .text
                }
                if !closed { mathStart = NSMaxRange(line) }
            } else if here {
                return inline(s, from: content.location, caret: caret)
            }
            if here || line.length == 0 { return .text }
            at = NSMaxRange(line)
        }
    }

    // `$a + $`는 닫는 `$` 앞이 공백이라 수식이 아니지만 `$a + x$`는 수식이다. 그래서 캐럿 자리에 글자가 이미 있는 것처럼
    // 읽어야 `$a + |$`에 넣은 기호가 수식에 든다.
    public static func typing(at caret: Int, in text: NSString) -> SourcePlace {
        let caret = min(max(0, caret), text.length)
        let probe = NSMutableString(string: text)
        probe.insert("x", at: caret)
        guard case .math(let display, let content, let fence) = at(caret, in: probe) else { return at(caret, in: probe) }
        return .math(display: display, content: NSRange(location: content.location, length: max(0, content.length - 1)), fence: fence)
    }

    static func inline(_ line: String, from offset: Int, caret: Int) -> SourcePlace {
        let chars = Array(line.utf16)
        let stop = caret - offset
        let dollar: UInt16 = 0x24, tick: UInt16 = 0x60, space: UInt16 = 0x20

        var k = 0
        while k < min(stop, chars.count) {
            let c = chars[k]
            if c == 0x5C {
                k += 2
                continue
            }
            if c == tick {
                var n = 0
                while k + n < chars.count, chars[k + n] == tick { n += 1 }
                if stop < k + n { return .text }
                var close: Int?
                var j = k + n
                while j + n <= chars.count {
                    if chars[j..<(j + n)].allSatisfy({ $0 == tick }), j + n == chars.count || chars[j + n] != tick, chars[j - 1] != tick {
                        close = j
                        break
                    }
                    j += 1
                }
                guard let close, stop > close else { return .inlineCode }
                k = close + n
                continue
            }
            if c == dollar {
                if k + 1 < chars.count, chars[k + 1] == dollar {
                    if stop == k + 1 { return .math(display: false, content: NSRange(location: offset + k + 1, length: 0)) }
                    k += 2
                    continue
                }
                var j = k + 1
                while j < chars.count, !(chars[j] == dollar && chars[j - 1] != 0x5C) { j += 1 }
                if j < chars.count {
                    if chars[k + 1] != space, chars[j - 1] != space {
                        if stop <= j { return .math(display: false, content: NSRange(location: offset + k + 1, length: j - k - 1)) }
                        k = j + 1
                        continue
                    }
                } else if k + 1 == stop || chars[k + 1] != space {
                    return .math(display: false, content: NSRange(location: offset + k + 1, length: chars.count - k - 1))
                }
            }
            k += 1
        }
        return .text
    }
}

struct Fence {
    let char: Character
    let count: Int
    let info: String

    init?(_ line: String) {
        let indent = line.prefix { $0 == " " }.count
        guard indent <= 3 else { return nil }
        let rest = line.dropFirst(indent)
        guard let first = rest.first, first == "`" || first == "~" else { return nil }
        let run = rest.prefix { $0 == first }.count
        guard run >= 3 else { return nil }
        let info = rest.dropFirst(run).trimmingCharacters(in: .whitespaces)
        if first == "`", info.contains("`") { return nil }
        char = first
        count = run
        self.info = info
    }

    func closes(_ open: Fence) -> Bool {
        char == open.char && count >= open.count && info.isEmpty
    }
}

enum SourceLines {
    static func content(_ line: NSRange, in text: NSString) -> NSRange {
        var length = line.length
        if length > 0, text.character(at: line.location + length - 1) == 0x0A { length -= 1 }
        return NSRange(location: line.location, length: length)
    }

    static func blockEnd(_ text: NSString, after line: NSRange) -> Int {
        var at = NSMaxRange(line)
        while at < text.length {
            let next = text.lineRange(for: NSRange(location: at, length: 0))
            let content = content(next, in: text)
            let s = text.substring(with: content)
            if s.trimmingCharacters(in: .whitespaces).hasSuffix("$$") {
                return content.location + (s as NSString).range(of: "$$", options: .backwards).location
            }
            at = NSMaxRange(next)
        }
        return text.length
    }

    static func fenceEnd(_ text: NSString, after line: NSRange, open: Fence) -> Int {
        var end = NSMaxRange(content(line, in: text))
        var at = NSMaxRange(line)
        while at < text.length {
            let next = text.lineRange(for: NSRange(location: at, length: 0))
            let body = content(next, in: text)
            if let f = Fence(text.substring(with: body)), f.closes(open) { return end }
            end = NSMaxRange(body)
            at = NSMaxRange(next)
        }
        return text.length
    }

    static func displayOpener(_ line: String) -> Int? {
        let prefix = line.prefix { $0 == " " || $0 == ">" }.utf16.count
        guard (line as NSString).substring(from: prefix).hasPrefix("$$") else { return nil }
        return prefix + 2
    }
}
