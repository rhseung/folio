import Foundation

/// Keys in the markdown source that do more than type: Enter carries a list or quote on, Tab indents lines or moves
/// through a formula's arguments, and brackets, `$`, backticks and `**` come in pairs. Pure functions of the text, so
/// the Mac and iPad editors share them and `swift test` checks them.
public enum SourceEditing {
    public struct Edit: Equatable, Sendable {
        public let range: NSRange
        public let text: String
        public let caret: Int
        /// Text left selected from the caret on, as when a wrapped selection stays selected.
        public let selected: Int

        public init(range: NSRange, text: String, caret: Int, selected: Int = 0) {
            self.range = range
            self.text = text
            self.caret = caret
            self.selected = selected
        }

        public var selection: NSRange { NSRange(location: caret, length: selected) }

        public func applied(to text: NSString) -> String { text.replacingCharacters(in: range, with: self.text) }
    }

    private static var marker: Regex<Substring> { #/^(?:(?:[-*+]|\d+[.)])(?: \[[ xX]\])?|>)[ \t]*$/# }
    private static var listLine: Regex<Substring> { /^\s*(?:[-*+]|\d+[.)])\s|^\s*>/ }

    // MARK: Enter

    /// What Enter does at the caret, or nil for a plain line break.
    public static func newline(_ text: NSString, _ selection: NSRange, inCode: Bool) -> Edit? {
        guard selection.length == 0, !inCode else { return nil }
        let caret = selection.location
        let full = text.lineRange(for: NSRange(location: caret, length: 0))
        let content = SourceLines.content(full, in: text)
        let line = text.substring(with: content)
        let atEnd = caret == NSMaxRange(content)

        // An empty nested item steps out one level, to its parent's indent, as in Obsidian.
        if atEnd, let nested = line.wholeMatch(of: #/^([ \t]+)(\S.*)$/#), String(nested.2).wholeMatch(of: marker) != nil {
            var at = content.location
            while at > 0 {
                let previous = text.lineRange(for: NSRange(location: at - 1, length: 0))
                at = previous.location
                let s = text.substring(with: previous).trimmingCharacters(in: .newlines)
                guard let m = s.firstMatch(of: #/^([ \t]*)(?:[-*+]|\d+[.)])\s/#) else {
                    if !s.trimmingCharacters(in: .whitespaces).isEmpty, s.first?.isWhitespace == false { break }
                    continue
                }
                guard m.1.count < nested.1.count else { continue }
                let insert = String(m.1) + nested.2
                return renumbered(text, Edit(range: content, text: insert, caret: content.location + insert.utf16.count))
            }
        }
        // Enter on an empty `- ` or `> ` ends the list or quote with a blank line, so what's typed next is a paragraph of
        // its own; left touching the block, CommonMark would read it as part of the last item.
        if atEnd, line.wholeMatch(of: marker) != nil {
            let next = NSMaxRange(full) < text.length ? text.substring(with: text.lineRange(for: NSRange(location: NSMaxRange(full), length: 0))) : ""
            if next.firstMatch(of: listLine) != nil { return nil }
            return Edit(range: content, text: "\n", caret: content.location + 1)
        }
        let head = line.utf16.count - (NSMaxRange(content) - caret)
        if let m = line.prefixMatch(of: #/^([ \t]*)((?:>[ \t]?)*)([ \t]*)(?:([-*+])|(\d+)([.)]))([ \t]+)(\[[ xX]\][ \t]+)?/#), m.0.utf16.count <= head {
            let mark = m.4.map(String.init) ?? "\((Int(m.5 ?? "0") ?? 0) + 1)\(m.6 ?? ".")"
            let insert = "\n" + m.1 + m.2 + m.3 + mark + m.7 + (m.8 == nil ? "" : "[ ] ")
            return renumbered(text, Edit(range: selection, text: insert, caret: caret + insert.utf16.count))
        }
        if let m = line.prefixMatch(of: #/^[ \t]*(?:>[ \t]?)+/#), m.0.utf16.count <= head {
            let insert = "\n" + m.0
            return Edit(range: selection, text: insert, caret: caret + insert.utf16.count)
        }
        return nil
    }

    /// Whether the edit view shows its hint for `/` at the caret: an empty line of text, the caret alone on it. Not in
    /// code or math, where `/` is typed as it is.
    public static func offersBlocks(in text: NSString, selection: NSRange) -> Bool {
        guard selection.length == 0, selection.location <= text.length else { return false }
        let line = SourceLines.content(text.lineRange(for: NSRange(location: selection.location, length: 0)), in: text)
        return line.length == 0 && SourcePlace.at(selection.location, in: text) == .text
    }

    // MARK: Tab

    public static let indentUnit = "    "

    /// Tab and Shift-Tab on lines: every line the selection touches moves by one indent, and numbered lists the lines
    /// are in are numbered again, so an item moved into a sublist starts it at 1 and the items after it close the gap.
    public static func indent(_ text: NSString, _ selection: NSRange, out: Bool, renumbering: Bool = true) -> Edit {
        let lines = text.lineRange(for: selection)
        var result = ""
        var shift = 0
        text.enumerateSubstrings(in: lines, options: [.byLines, .substringNotRequired]) { _, line, enclosing, _ in
            let s = text.substring(with: line)
            if out {
                let n = s.prefix(4).prefix { $0 == " " }.count + (s.first == "\t" ? 1 : 0)
                result += String(s.dropFirst(min(n, s.count)))
                if line.location <= selection.location { shift -= min(n, max(0, selection.location - line.location)) }
            } else {
                result += indentUnit + s
                if line.location <= selection.location { shift += indentUnit.count }
            }
            result += text.substring(with: NSRange(location: NSMaxRange(line), length: NSMaxRange(enclosing) - NSMaxRange(line)))
        }
        let edit = Edit(range: lines, text: result, caret: max(lines.location, selection.location + shift))
        return renumbering ? renumbered(text, edit) : edit
    }

    /// What Tab does: expand a snippet whose trigger is just before the caret, move to a formula's next argument, or
    /// indent. Shift-Tab steps back through the arguments, or outdents. AsciiMath puts arguments in brackets, as
    /// `frac(a)(b)`, where TeX uses braces.
    public static func tab(_ text: NSString, _ selection: NSRange, back: Bool, catalog: CompletionCatalog) -> Edit {
        let here = catalog.at(SourcePlace.at(selection.location, in: text))
        return tab(text, selection, back: back, snippets: here.snippets, asciiMath: !here.tex)
    }

    public static func tab(_ text: NSString, _ selection: NSRange, back: Bool, snippets: [Snippet] = [], asciiMath: Bool = false) -> Edit {
        let place = SourcePlace.at(selection.location, in: text)
        if !back, selection.length == 0, let (snippet, range) = Snippet.match(snippets, in: text, caret: selection.location, place: place) {
            return snippet.edit(replacing: range)
        }
        if case .math(_, let content, _) = place, let slot = slot(text, from: selection.location, in: content, back: back, opener: asciiMath ? 0x28 : 0x7B) {
            return Edit(range: NSRange(location: slot, length: 0), text: "", caret: slot)
        }
        // Lines in a code block are code: `1.` there is not a list to number again.
        if case .code = place { return indent(text, selection, out: back, renumbering: false) }
        return indent(text, selection, out: back)
    }

    /// The next argument slot of the formula the caret is in: just inside the next `opener`, else just past the
    /// formula's closing delimiter. Back: just inside the `opener` before the one the caret is in, else the formula's
    /// start. Read from the text, not remembered, so slots still line up after anything typed into them.
    static func slot(_ text: NSString, from caret: Int, in content: NSRange, back: Bool, opener: UInt16 = 0x7B) -> Int? {
        var starts: [Int] = []
        var i = content.location
        while i < NSMaxRange(content) {
            if text.character(at: i) == opener, i == 0 || text.character(at: i - 1) != 0x5C { starts.append(i + 1) }
            i += 1
        }
        if back {
            if let s = starts.last(where: { $0 < caret }) { return s }
            return caret == content.location ? nil : content.location
        }
        if let s = starts.first(where: { $0 > caret }) { return s }
        var end = NSMaxRange(content)
        while end < text.length, text.character(at: end) == 0x24 { end += 1 }
        return end == caret ? nil : end
    }

    // MARK: Pairs

    private static let pairs: [UInt16: UInt16] = [0x28: 0x29, 0x5B: 0x5D, 0x7B: 0x7D]
    /// What a selection is wrapped in by typing its opener: brackets anywhere, emphasis, code and math marks in text.
    private static let wraps: [UInt16: UInt16] = [0x5B: 0x5D, 0x28: 0x29]
    private static let textWraps: [UInt16: UInt16] = wraps.merging([0x2A: 0x2A, 0x60: 0x60, 0x24: 0x24]) { a, _ in a }

    /// What typing closes, as the input guide lists it. `$`, backticks and `**` pair by rules of their own in `typed`,
    /// not by a table, so the list is kept beside them and a test types each one.
    public static let shownPairs = ["(", "[", "{", "$", "`", "**"]
    /// What a selection is wrapped in by typing it, in text; the test types each one.
    public static let shownWraps = ["*", "`", "$", "[", "("]
    /// The lines Return carries on, as the guide lists them; the test ends each one.
    public static let shownListMarks = ["-", "1.", "- [ ]", ">"]
    private static let closers: Set<UInt16> = [0x29, 0x5D, 0x7D]
    /// A pair opens only before these, the end of the line, or space, so typing in front of a word doesn't leave a
    /// closer stranded after it.
    private static let before: Set<UInt16> = [0x29, 0x5D, 0x7D, 0x3A, 0x3B, 0x3E, 0x2C, 0x2E, 0x24, 0x2A, 0x60]

    /// What typing `typed` does at the selection, or nil to type it as it is. Inside code, only brackets pair: `*`,
    /// backticks and `$` there are the code's own characters.
    public static func typed(_ typed: String, in text: NSString, selection: NSRange) -> Edit? {
        let units = Array(typed.utf16)
        guard units.count == 1 else { return nil }
        let c = units[0]
        let place = SourcePlace.at(selection.location, in: text)
        let at = selection.location
        let prev: UInt16? = at > 0 ? text.character(at: at - 1) : nil
        let prev2: UInt16? = at > 1 ? text.character(at: at - 2) : nil
        let end = NSMaxRange(selection)
        let next: UInt16? = end < text.length ? text.character(at: end) : nil
        let next2: UInt16? = end + 1 < text.length ? text.character(at: end + 1) : nil

        if selection.length > 0 {
            guard let close = (place == .text ? textWraps : wraps)[c] else { return nil }
            let inner = text.substring(with: selection)
            return Edit(range: selection, text: typed + inner + String(utf16CodeUnits: [close], count: 1), caret: at + 1, selected: selection.length)
        }
        let step = Edit(range: NSRange(location: at, length: 0), text: "", caret: at + 1)
        let opensBefore = next.map { isSpace($0) || before.contains($0) } ?? true

        if let close = pairs[c] {
            guard opensBefore else { return nil }
            return Edit(range: selection, text: typed + String(utf16CodeUnits: [close], count: 1), caret: at + 1)
        }
        if closers.contains(c) { return next == c ? step : nil }
        switch c {
        case 0x24:
            if place.isCode { return nil }
            // `$|$` and another `$`: display math, `$$|$$`.
            if prev == 0x24, next == 0x24, prev2 != 0x24, next2 != 0x24, !place.isMath || isEmptyPair(place) {
                return Edit(range: selection, text: "$$", caret: at + 1)
            }
            if next == 0x24 { return step }
            if place.isMath { return nil }
            guard opensBefore, !(prev.map(isWord) ?? false) else { return nil }
            return Edit(range: selection, text: "$$", caret: at + 1)
        case 0x60:
            guard place == .text || place == .inlineCode else { return nil }
            if next == 0x60 { return step }
            if place == .inlineCode { return nil }
            // A third backtick after two makes a fence, not another pair.
            guard prev != 0x60, opensBefore, !(prev.map(isWord) ?? false) else { return nil }
            return Edit(range: selection, text: "``", caret: at + 1)
        case 0x2A:
            guard place == .text else { return nil }
            if prev == 0x2A, prev2 != 0x2A, next != 0x2A, opensBefore {
                return Edit(range: selection, text: "***", caret: at + 1)
            }
            if next == 0x2A, let prev, !isSpace(prev) { return step }
            return nil
        default:
            return nil
        }
    }

    private static func isEmptyPair(_ place: SourcePlace) -> Bool {
        if case .math(false, let content, _) = place { return content.length == 0 }
        return false
    }

    /// Backspace between an empty pair takes both halves.
    public static func deleteBackward(in text: NSString, selection: NSRange) -> Edit? {
        let at = selection.location
        guard selection.length == 0, at > 0, at < text.length else { return nil }
        let prev = text.character(at: at - 1), next = text.character(at: at)
        let marks: Set<UInt16> = switch SourcePlace.at(at, in: text) {
        case .text: [0x24, 0x60, 0x2A]
        case .inlineCode: [0x60]
        case .math: [0x24]
        case .code: []
        }
        guard pairs[prev] == next || (prev == next && marks.contains(prev)) else { return nil }
        return Edit(range: NSRange(location: at - 1, length: 2), text: "", caret: at - 1)
    }

    private static func isSpace(_ c: UInt16) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A }

    private static func isWord(_ c: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(c) else { return true }
        return CharacterSet.alphanumerics.contains(scalar)
    }

    // MARK: Numbering

    /// `edit` and the renumbering of the numbered lists it lands in, as one edit.
    static func renumbered(_ text: NSString, _ edit: Edit) -> Edit {
        let after = edit.applied(to: text) as NSString
        let changes = renumber(after, around: NSRange(location: edit.range.location, length: edit.text.utf16.count))
        guard !changes.isEmpty else { return edit }
        let final = NSMutableString(string: after)
        var caret = edit.caret
        for (range, digits) in changes.reversed() {
            final.replaceCharacters(in: range, with: digits)
        }
        for (range, digits) in changes where NSMaxRange(range) <= edit.caret {
            caret += digits.utf16.count - range.length
        }
        return diff(text, final, caret: caret)
    }

    /// The numbers to set, in order, in the numbered lists of the list block holding `range`. Each run of items at one
    /// indent counts on from its first number; a run inside another item starts at 1, since it was made by indenting.
    public static func renumber(_ text: NSString, around range: NSRange) -> [(NSRange, String)] {
        let item = #/^([ \t]*)(?:(?:>[ \t]?)*)([ \t]*)(?:[-*+]|(\d+)([.)]))[ \t]/#
        var lines: [NSRange] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            lines.append(line)
        }
        guard let hit = lines.firstIndex(where: { NSLocationInRange(range.location, $0) || NSMaxRange($0) == range.location }) else { return [] }
        // A fence ends the block too: a list right before or after a code block isn't numbered across it.
        let inList = { (i: Int) -> Bool in
            let s = text.substring(with: lines[i])
            return !s.trimmingCharacters(in: .whitespaces).isEmpty && Fence(String(s.drop { $0 == " " || $0 == "\t" })) == nil
        }
        guard inList(hit) else { return [] }
        var first = hit, last = hit
        while first > 0, inList(first - 1) { first -= 1 }
        while last + 1 < lines.count, inList(last + 1) { last += 1 }

        struct Level { let indent: Int; var next: Int?; let delimiter: String? }
        var stack: [Level] = []
        var out: [(NSRange, String)] = []
        for i in first...last {
            let s = text.substring(with: lines[i])
            guard let m = s.prefixMatch(of: item) else { continue }
            let indent = (String(m.1) + String(m.2)).replacingOccurrences(of: "\t", with: indentUnit).count
            while let top = stack.last, top.indent > indent { stack.removeLast() }
            guard let digits = m.3 else {
                if let top = stack.last, top.indent == indent { stack.removeLast() }
                stack.append(Level(indent: indent, next: nil, delimiter: nil))
                continue
            }
            let delimiter = String(m.4 ?? ".")
            if let top = stack.last, top.indent == indent, let n = top.next, top.delimiter == delimiter {
                let digitRange = NSRange(m.3!.startIndex..<m.3!.endIndex, in: s)
                if Int(digits) != n { out.append((NSRange(location: lines[i].location + digitRange.location, length: digitRange.length), String(n))) }
                stack[stack.count - 1].next = n + 1
            } else {
                if let top = stack.last, top.indent == indent { stack.removeLast() }
                let nested = !stack.isEmpty
                let start = nested ? 1 : Int(digits) ?? 1
                if nested, Int(digits) != 1 {
                    let digitRange = NSRange(m.3!.startIndex..<m.3!.endIndex, in: s)
                    out.append((NSRange(location: lines[i].location + digitRange.location, length: digitRange.length), "1"))
                }
                stack.append(Level(indent: indent, next: start + 1, delimiter: delimiter))
            }
        }
        return out
    }

    /// One edit taking `old` to `new`: the span between what they share at the start and at the end.
    static func diff(_ old: NSString, _ new: NSString, caret: Int) -> Edit {
        var a = 0, b = 0
        let n = min(old.length, new.length)
        while a < n, old.character(at: a) == new.character(at: a) { a += 1 }
        while b < n - a, old.character(at: old.length - 1 - b) == new.character(at: new.length - 1 - b) { b += 1 }
        return Edit(range: NSRange(location: a, length: old.length - a - b),
                    text: new.substring(with: NSRange(location: a, length: new.length - a - b)), caret: caret)
    }
}
