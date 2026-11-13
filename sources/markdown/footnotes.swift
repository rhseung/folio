import Foundation
import Markdown

/// GFM footnotes: `[^label]` in the text, and `[^label]: text` at the start of a line defining it.
///
/// Read here, not by the parser: swift-markdown 0.9 doesn't turn on cmark-gfm's footnote extension. Before parsing,
/// a definition's `[` is swapped for `marker` (same length in UTF-16, so offsets still match the source). Left as it
/// is, `[^1]: https://…` is a CommonMark link definition: it vanishes, and every `[^1]` becomes a link to it. Swapped,
/// the definition stays a paragraph that starts with the marker, and a reference stays text, found in the rendered
/// inline HTML as wikilinks are.
public enum Footnotes {
    public static let marker: Character = "\u{E001}"

    static var definitionLine: Regex<(Substring, Substring)> { #/^ {0,3}\[\^([^\]\s]+)\]:/# }
    static var reference: Regex<(Substring, Substring)> { #/\[\^([^\]\s]+)\]/# }
    /// A masked definition's start as the paragraph's first text holds it, with the space after the colon.
    static var maskedStart: Regex<(Substring, Substring)> { #/^\x{E001}\^([^\]\s]+)\]:[ \t]*/# }

    /// Labels match ignoring case, as link labels do.
    static func key(_ label: some StringProtocol) -> String { label.lowercased() }

    public static func mask(_ text: String) -> String {
        let out = NSMutableString(string: text)
        for line in lines(text) where line.definition != nil {
            out.replaceCharacters(in: NSRange(location: line.bracket, length: 1), with: String(marker))
        }
        return out as String
    }

    /// Where footnote syntax is in the source, for the editor's colors: the label and the marks around it.
    public struct Mark: Equatable, Sendable {
        /// From `[` to `]`, or to the colon for a definition.
        public var range: NSRange
        public var label: NSRange
        public var definition: Bool
    }

    /// Every definition at a line's start and every reference elsewhere, outside fenced code. Inline code and math are
    /// the caller's to leave out: it knows where they are.
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
        /// The label's range in the whole text when the line defines a footnote.
        var definition: NSRange?
        /// Where the definition's `[` is in the whole text.
        var bracket: Int
    }

    /// The lines outside fenced code, which is where footnotes are.
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

/// The footnotes of one note as its page is drawn: what each label says, and the numbers given out in the order
/// the references come. A class, so a table cell's renderer, a copy, numbers on from the note's.
final class FootnoteBook {
    let definitions: [String: [Markup]]
    private(set) var numbered: [String] = []
    private var uses: [String: Int] = [:]

    /// The definitions anywhere in `document`; the first one of a label counts, as in GFM.
    init(_ document: Markup) {
        var found: [String: [Markup]] = [:]
        func walk(_ node: Markup) {
            if let p = node as? Paragraph, Self.label(of: p) != nil {
                for (label, inlines) in Self.split(p) where found[Footnotes.key(label)] == nil { found[Footnotes.key(label)] = inlines }
                return
            }
            for child in node.children { walk(child) }
        }
        walk(document)
        definitions = found
    }

    static func label(of node: Markup?) -> String? {
        guard let text = node as? Markdown.Text, text.string.first == Footnotes.marker,
            let m = text.string.prefixMatch(of: Footnotes.maskedStart)
        else { return nil }
        return String(m.1)
    }

    static func label(of p: Paragraph) -> String? { label(of: p.child(at: 0)) }

    /// Definitions on the lines right after one another are one paragraph to CommonMark, each line after the first
    /// joined to it by a soft break; each starts a footnote of its own, as in GFM.
    static func split(_ p: Paragraph) -> [(String, [Markup])] {
        var out: [(String, [Markup])] = []
        let inlines = Array(p.inlineChildren).map { $0 as Markup }
        for (i, node) in inlines.enumerated() {
            if let label = label(of: node), i == 0 || inlines[i - 1] is SoftBreak {
                if i > 0, !out.isEmpty { out[out.count - 1].1.removeLast() }
                out.append((label, [node]))
            } else if !out.isEmpty {
                out[out.count - 1].1.append(node)
            }
        }
        return out
    }

    func isDefinition(_ p: Paragraph) -> Bool {
        Self.label(of: p).map { definitions[Footnotes.key($0)] != nil } ?? false
    }

    /// The footnote's number and which use of it this is (1 for the first), or nil when nothing defines it.
    func use(_ label: String) -> (number: Int, use: Int)? {
        let key = Footnotes.key(label)
        guard definitions[key] != nil else { return nil }
        if !numbered.contains(key) { numbered.append(key) }
        uses[key, default: 0] += 1
        return (numbered.firstIndex(of: key)! + 1, uses[key]!)
    }

    func uses(of key: String) -> Int { uses[key] ?? 0 }
}
