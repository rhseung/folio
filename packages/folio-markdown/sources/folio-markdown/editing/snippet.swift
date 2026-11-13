import Foundation

/// A short trigger typed and expanded into a longer piece, as `mk` into `$…$`. `$1`, `$2` … mark where the caret goes,
/// lowest first, and `$0` where it goes when nothing else is marked; any other `$` is the character itself, so the
/// math delimiters need no escaping. Tab moves on through a formula's arguments from there (`SourceEditing.slot`).
public struct Snippet: Equatable, Sendable {
    public var trigger: String
    public var body: String
    /// Expands only inside math, or only outside it.
    public var inMath: Bool

    public init(trigger: String, body: String, inMath: Bool) {
        self.trigger = trigger
        self.body = body
        self.inMath = inMath
    }

    /// The body without its caret marks, and where the caret goes in it (UTF-16).
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

    /// The snippet whose trigger ends at the caret, longest first, and the trigger's range. A trigger of letters
    /// needs no letter before it, so `mk` doesn't fire at the end of `bookmark`; none fires after `\`, where the letters
    /// are a command's name.
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
