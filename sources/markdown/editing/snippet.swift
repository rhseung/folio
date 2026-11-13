import Foundation

public struct Snippet: Equatable, Sendable {
    public var trigger: String
    public var body: String
    public var inMath: Bool

    public init(trigger: String, body: String, inMath: Bool) {
        self.trigger = trigger
        self.body = body
        self.inMath = inMath
    }

    public var expanded: (text: String, caret: Int) {
        let units = Array(body.utf16)
        var out: [UInt16] = []
        var stops: [(n: Int, at: Int)] = []
        var i = 0
        while i < units.count {
            if units[i] == 0x24, i + 1 < units.count, (0x30...0x39).contains(units[i + 1]) {
                stops.append((Int(units[i + 1] - 0x30), out.count))
                i += 2
                continue
            }
            out.append(units[i])
            i += 1
        }
        let caret = stops.filter { $0.n > 0 }.min { $0.n < $1.n }?.at ?? stops.first { $0.n == 0 }?.at ?? out.count
        return (String(utf16CodeUnits: out, count: out.count), caret)
    }

    public func edit(replacing range: NSRange) -> SourceEditing.Edit {
        let (text, caret) = expanded
        return SourceEditing.Edit(range: range, text: text, caret: range.location + caret)
    }

    // 글자로 된 트리거는 앞에 글자가 없어야 펼치므로 `bookmark` 끝의 `mk`는 펼치지 않는다. `\` 뒤의 글자는 명령
    // 이름이라 어떤 트리거도 펼치지 않는다.
    public static func match(_ snippets: [Snippet], in text: NSString, caret: Int, place: SourcePlace) -> (Snippet, NSRange)? {
        guard !place.isCode else { return nil }
        let candidates = snippets.filter { $0.inMath == place.isMath && !$0.trigger.isEmpty }.sorted {
            $0.trigger.utf16.count > $1.trigger.utf16.count
        }
        for snippet in candidates {
            let n = snippet.trigger.utf16.count
            guard caret >= n, text.substring(with: NSRange(location: caret - n, length: n)) == snippet.trigger else { continue }
            let start = caret - n
            if case .math(_, let content, _) = place, start < content.location { continue }
            if start > 0 {
                let before = text.character(at: start - 1)
                if before == 0x5C { continue }
                if let first = snippet.trigger.unicodeScalars.first, CharacterSet.letters.contains(first),
                    let scalar = Unicode.Scalar(before), CharacterSet.alphanumerics.contains(scalar)
                {
                    continue
                }
            }
            return (snippet, NSRange(location: start, length: n))
        }
        return nil
    }
}
