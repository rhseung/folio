import Foundation

/// Keys in the markdown source that do more than type: Enter carries a list or quote on, Tab indents lines.
enum SourceEditing {
    struct Edit: Equatable {
        let range: NSRange
        let text: String
        let caret: Int
    }

    private static var marker: Regex<Substring> { #/^(?:(?:[-*+]|\d+[.)])(?: \[[ xX]\])?|>)[ \t]*$/# }
    private static var listLine: Regex<Substring> { /^\s*(?:[-*+]|\d+[.)])\s|^\s*>/ }

    /// What Enter does at the caret, or nil for a plain line break.
    static func newline(_ text: NSString, _ selection: NSRange, inCode: Bool) -> Edit? {
        guard selection.length == 0, !inCode else { return nil }
        let caret = selection.location
        let full = text.lineRange(for: NSRange(location: caret, length: 0))
        let content = NSRange(location: full.location, length: full.length - (text.substring(with: full).hasSuffix("\n") ? 1 : 0))
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
                return Edit(range: content, text: insert, caret: content.location + insert.utf16.count)
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
            return Edit(range: selection, text: insert, caret: caret + insert.utf16.count)
        }
        if let m = line.prefixMatch(of: #/^[ \t]*(?:>[ \t]?)+/#), m.0.utf16.count <= head {
            let insert = "\n" + m.0
            return Edit(range: selection, text: insert, caret: caret + insert.utf16.count)
        }
        return nil
    }

    static let indentUnit = "    "

    /// Tab and Shift-Tab: every line the selection touches moves by one indent, as in CodeMirror.
    static func indent(_ text: NSString, _ selection: NSRange, out: Bool) -> Edit {
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
        return Edit(range: lines, text: result, caret: max(lines.location, selection.location + shift))
    }
}
