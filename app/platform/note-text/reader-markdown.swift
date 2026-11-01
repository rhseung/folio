import Foundation

/// Writes a block of the read view back as markdown, from the attributes `ReaderBuilder` put on it. A block is typed
/// into only if this reproduces its source exactly, so an edit never rewrites markdown the note didn't change.
enum ReaderMarkdown {
    static func block(_ text: NSAttributedString, _ range: NSRange, kind: ReaderBlock.Kind, source: String, id: String? = nil) -> String? {
        let tail = id.map { " ^" + $0 } ?? ""
        switch kind {
        case .paragraph:
            return lines(inline(text, range)) + tail
        case .heading(let level):
            return String(repeating: "#", count: level) + " " + lines(inline(text, range))
        case .list:
            return list(text, range, source: source)
        case .other:
            return nil
        }
    }

    // MARK: Lists

    private static func list(_ text: NSAttributedString, _ range: NSRange, source: String) -> String? {
        let unit = source.firstMatch(of: #/(?m)^([ \t]+)(?:[-*+]|\d+[.)])(?:\s|$)/#).map { String($0.1) } ?? "    "
        let bullet = source.firstMatch(of: #/^\s*([-*+])\s/#).map { String($0.1) } ?? "-"
        var out: [String] = []
        var counters: [Int] = []
        var failed = false
        (text.string as NSString).enumerateSubstrings(in: range, options: [.byParagraphs, .substringNotRequired]) { _, line, _, stop in
            guard line.length > 0, let info = text.attribute(.noteListItem, at: line.location, effectiveRange: nil) as? ListInfo else {
                failed = true
                stop.pointee = true
                return
            }
            let depth = info.depth
            if depth < counters.count {
                counters[depth] += 1
                counters.removeSubrange((depth + 1)...)
            } else {
                counters += Array(repeating: info.number, count: depth + 1 - counters.count)
            }
            let mark = info.ordered ? "\(counters[depth])." : bullet
            var done: Bool?
            text.enumerateAttribute(.noteTask, in: line) { value, _, _ in if let v = value as? Bool { done = v } }
            var body = lines(inline(text, line).trimmingCharacters(in: .whitespaces))
            if let done { body = (done ? "[x]" : "[ ]") + (body.isEmpty ? "" : " " + body) }
            body += info.id.map { " ^" + $0 } ?? ""
            let indent = String(repeating: unit, count: depth)
            let hang = indent + String(repeating: " ", count: mark.count + 1)
            out.append(indent + mark + (body.isEmpty ? "" : " " + body.replacingOccurrences(of: "\n", with: "\n" + hang)))
        }
        return failed ? nil : out.joined(separator: "\n")
    }

    // MARK: Inline text

    private struct Mark: Equatable {
        enum Kind: Int { case emphasis, strong, strike, link }
        let kind: Kind
        var href = ""
        var open: String { kind == .link ? "[" : token }
        var close: String { kind == .link ? "](\(href))" : token }
        private var token: String { [.emphasis: "*", .strong: "**", .strike: "~~"][kind] ?? "" }
    }

    /// A stretch of one line written with the same marks: escaped text, a code span, or an atom's own source.
    private struct Piece {
        var marks: [Mark]
        var text: String
        var raw: Bool
    }

    private static func marks(_ attributes: [NSAttributedString.Key: Any]) -> [Mark] {
        let set = InlineMarks(rawValue: attributes[.noteMarks] as? Int ?? 0)
        var list: [Mark] = []
        if set.contains(.emphasis) { list.append(Mark(kind: .emphasis)) }
        if set.contains(.strong) { list.append(Mark(kind: .strong)) }
        if set.contains(.strike) { list.append(Mark(kind: .strike)) }
        if let href = attributes[.noteLink] as? String { list.append(Mark(kind: .link, href: href)) }
        return list
    }

    /// The range's lines as markdown, joined by `\n`.
    static func inline(_ text: NSAttributedString, _ range: NSRange) -> String {
        var lines: [[Piece]] = [[]]
        var code: (marks: [Mark], text: String)?
        var lastAtom: NoteAtom?
        func flushCode() {
            guard let c = code else { return }
            let longest = c.text.matches(of: #/`+/#).map(\.0.count).max() ?? 0
            let fence = String(repeating: "`", count: longest + 1)
            let body = c.text.hasPrefix("`") || c.text.hasSuffix("`") ? " \(c.text) " : c.text
            lines[lines.count - 1].append(Piece(marks: c.marks, text: fence + body + fence, raw: true))
            code = nil
        }
        let string = text.string as NSString
        text.enumerateAttributes(in: range) { attributes, r, _ in
            let m = marks(attributes)
            if let atom = attributes[.noteAtom] as? NoteAtom {
                flushCode()
                // An atom can come in several runs; it's written once.
                if atom !== lastAtom, !atom.source.isEmpty { lines[lines.count - 1].append(Piece(marks: m, text: atom.source, raw: true)) }
                lastAtom = atom
                return
            }
            lastAtom = nil
            let isCode = InlineMarks(rawValue: attributes[.noteMarks] as? Int ?? 0).contains(.code)
            let parts = string.substring(with: r).replacingOccurrences(of: "\u{00A0}", with: " ").split(separator: "\u{2028}", omittingEmptySubsequences: false)
            for (i, part) in parts.enumerated() {
                if i > 0 {
                    flushCode()
                    lines.append([])
                }
                guard !part.isEmpty else { continue }
                if isCode {
                    if let c = code, c.marks != m { flushCode() }
                    code = (m, (code?.text ?? "") + part)
                } else {
                    flushCode()
                    if let last = lines[lines.count - 1].last, !last.raw, last.marks == m {
                        lines[lines.count - 1][lines[lines.count - 1].count - 1].text += part
                    } else {
                        lines[lines.count - 1].append(Piece(marks: m, text: String(part), raw: false))
                    }
                }
            }
        }
        flushCode()
        return lines.map(write).joined(separator: "\n")
    }

    /// Opens and closes marks around the pieces, the one running longest outside, and keeps spaces outside them where
    /// they don't stop `**` from closing.
    private static func write(_ pieces: [Piece]) -> String {
        var out = ""
        var stack: [(mark: Mark, opened: Bool)] = []
        func close(from k: Int) {
            while stack.count > k {
                let entry = stack.removeLast()
                guard entry.opened else { continue }
                let trailing = out.reversed().prefix { $0 == " " || $0 == "\t" }.count
                out.insert(contentsOf: entry.mark.close, at: out.index(out.endIndex, offsetBy: -trailing))
            }
        }
        for (i, piece) in pieces.enumerated() {
            if let k = stack.firstIndex(where: { !piece.marks.contains($0.mark) }) { close(from: k) }
            let missing = piece.marks.filter { m in !stack.contains { $0.mark == m } }
            let span = { (m: Mark) in pieces[i...].prefix { $0.marks.contains(m) }.count }
            for m in missing.sorted(by: { (span($0), -$0.kind.rawValue) > (span($1), -$1.kind.rawValue) }) { stack.append((m, false)) }
            let text = piece.raw ? piece.text : escape(piece.text)
            let lead = text.prefix { $0 == " " || $0 == "\t" }
            out += lead
            let rest = text.dropFirst(lead.count)
            guard !rest.isEmpty else { continue }
            for k in stack.indices where !stack[k].opened {
                out += stack[k].mark.open
                stack[k].opened = true
            }
            out += rest
        }
        close(from: 0)
        return out
    }

    /// A typed character that markdown would read as markup gets a backslash. `*` and `_` with space on both sides,
    /// and `_` inside a word, can't be emphasis and stay bare, as people write them.
    static func escape(_ s: String) -> String {
        let c = Array(s)
        var out = ""
        for i in c.indices {
            let ch = c[i], prev = i > 0 ? c[i - 1] : nil, next = i + 1 < c.count ? c[i + 1] : nil
            let spaced = prev?.isWhitespace == true && next?.isWhitespace == true
            let word = { (x: Character?) in x.map { $0.isLetter || $0.isNumber } ?? false }
            let inWord = ch == "_" && word(prev) && word(next)
            let markup = ch == "\\" || ch == "`" || ch == "$" || ((ch == "*" || ch == "_") && !spaced && !inWord)
                || (ch == "[" && next == "[") || (ch == "]" && next == "(") || (ch == "~" && next == "~")
                || (ch == "<" && next.map { $0.isASCII && ($0.isLetter || "/!?".contains($0)) } == true)
            out += markup ? "\\\(ch)" : "\(ch)"
        }
        return out
    }

    /// A typed line that would start a block (`# `, `- `, `> `, `1. `) is kept as text.
    static func escapeLineStart(_ line: String) -> String {
        if let m = line.prefixMatch(of: #/(\d+)([.)])(\s|$)/#) { return m.1 + "\\" + line.dropFirst(m.1.count) }
        return line.prefixMatch(of: #/#{1,6}(\s|$)|[-+](\s|$)|>|={3,}\s*$/#) != nil ? "\\" + line : line
    }

    static func lines(_ s: String) -> String {
        var t = s
        while t.hasSuffix("\n") { t.removeLast() }
        return t.split(separator: "\n", omittingEmptySubsequences: false).map { escapeLineStart(String($0)) }.joined(separator: "\n")
    }
}
