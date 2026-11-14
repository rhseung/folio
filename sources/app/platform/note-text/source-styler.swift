import FolioDomain
import FolioMarkdown
import Markdown

#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension NSAttributedString.Key {
    static let noteHref = NSAttributedString.Key("folio.href")
    static let noteWiki = NSAttributedString.Key("folio.wiki")
    static let noteTask = NSAttributedString.Key("folio.task")
    static let noteMath = NSAttributedString.Key("folio.math")
    static let noteMathBlock = NSAttributedString.Key("folio.math-block")
    static let noteMathSyntax = NSAttributedString.Key("folio.math-syntax")
    static let noteImage = NSAttributedString.Key("folio.image")
    static let noteCode = NSAttributedString.Key("folio.code")
    static let noteCaret = NSAttributedString.Key("folio.caret")
}

extension MathSyntax {
    init(_ fence: MathFence.Syntax) {
        switch fence {
        case .latex: self = .latex
        case .asciimath: self = .asciimath
        }
    }
}

extension NSAttributedString {
    func mathFence(at index: Int) -> MathSyntax? {
        guard index < length else { return nil }
        return (attribute(.noteMathSyntax, at: index, effectiveRange: nil) as? String).flatMap(MathSyntax.init(rawValue:))
    }
}

@MainActor struct SourceStyler {
    var accent: CourseAccent
    var syntax: MathSyntax
    var baseURL: URL?
    var dark: Bool

    private static let heading = NSAttributedString.Key("folio.s.heading")
    private static let weight = NSAttributedString.Key("folio.s.weight")
    private static let italic = NSAttributedString.Key("folio.s.italic")
    private static let mono = NSAttributedString.Key("folio.s.mono")
    private static let mark = NSAttributedString.Key("folio.s.mark")

    // 따로 스타일을 입힌 뒤 결과가 달라진 문단만 바꾼다. 전체를 바꾸면 TextKit이 키를 누를 때마다 노트 전체의 배치를 버리고 화면 위쪽의 높이를 다시 추정한다.
    func style(_ storage: NSTextStorage) {
        let fresh = styled(storage.string)
        let ns = storage.string as NSString
        var changed: [NSRange] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs, .substringNotRequired]) { _, _, p, _ in
            if !NoteAttributes.same(storage, fresh, in: p) { changed.append(p) }
        }
        guard !changed.isEmpty else { return }
        storage.beginEditing()
        for p in changed {
            fresh.enumerateAttributes(in: p) { attributes, r, _ in storage.setAttributes(attributes, range: r) }
        }
        storage.endEditing()
    }

    func styled(_ text: String) -> NSMutableAttributedString {
        let storage = NSMutableAttributedString(string: text)
        let all = NSRange(location: 0, length: storage.length)
        let lines = Self.lines(text)
        let math = MathScan(text: text, lines: lines)
        let masked = Footnotes.mask(DraftItem.mask(math.masked(text)))
        let document = Document(parsing: masked)
        var w = Writer(storage: storage, columns: Columns(masked), text: text as NSString)

        storage.beginEditing()
        storage.setAttributes([.foregroundColor: NoteLook.text, .paragraphStyle: Self.paragraph()], range: all)
        w.walk(document, styler: self)
        for i in DraftItem.dashes(in: text) {
            w.set(
                NSRange(location: i, length: 1),
                [.foregroundColor: accent.native.withAlphaComponent(0.85), Self.weight: PlatformFont.Weight.semibold.rawValue])
        }

        for line in lines where !w.inCode(line) {
            let s = (text as NSString).substring(with: line)
            if let m = s.firstMatch(of: BlockID.pattern) { w.marks.append(Self.nsRange(m.range, in: s, at: line.location)) }
        }
        let masked16 = masked as NSString
        for m in Self.escape.matches(in: masked, range: NSRange(location: 0, length: masked16.length)) where !w.inCode(m.range) {
            w.marks.append(NSRange(location: m.range.location, length: 1))
        }
        for m in text.matches(of: WikiLink.pattern) {
            let r = NSRange(m.range, in: text)
            guard !w.inCode(r, orTable: false), !math.covers(r) else { continue }
            let open = m.1.isEmpty ? 2 : 3
            w.set(
                r,
                [
                    .foregroundColor: accent.inkNative, Self.weight: PlatformFont.Weight.medium.rawValue,
                    .noteWiki: WikiLink(m).target, .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: accent.native.withAlphaComponent(0.4),
                ])
            w.marks.append(NSRange(location: r.location, length: open))
            w.marks.append(NSRange(location: NSMaxRange(r) - 2, length: 2))
            if WikiLink(m).noteID != nil {
                w.marks.append(NSRange(m.2.startIndex..<m.2.endIndex, in: text))
                if let alias = m.5 {
                    let bar = text.index(before: alias.startIndex)
                    let escaped = bar > m.range.lowerBound && text[text.index(before: bar)] == "\\"
                    w.marks.append(NSRange((escaped ? text.index(before: bar) : bar)..<alias.startIndex, in: text))
                }
            }
        }
        for (r, link) in AppLink.links(in: text) where !w.inCode(r, orTable: false) && !math.covers(r) {
            let taken =
                storage.attribute(.noteWiki, at: r.location, effectiveRange: nil) != nil
                || storage.attribute(.noteHref, at: r.location, effectiveRange: nil) != nil
            guard !taken else { continue }
            w.set(
                r,
                [
                    .foregroundColor: accent.inkNative, .noteHref: link.string, .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: accent.native.withAlphaComponent(0.4),
                ])
        }
        for mark in Footnotes.marks(in: text) where !w.inCode(mark.range) && !math.covers(mark.range) {
            w.set(
                mark.label,
                [.foregroundColor: accent.inkNative, Self.weight: (mark.definition ? PlatformFont.Weight.semibold : .medium).rawValue])
            w.marks.append(NSRange(location: mark.range.location, length: mark.label.location - mark.range.location))
            w.marks.append(NSRange(location: NSMaxRange(mark.label), length: NSMaxRange(mark.range) - NSMaxRange(mark.label)))
        }

        for span in math.inline {
            w.set(span.range, [Self.mono: true, .foregroundColor: accent.inkNative, .noteMath: span.tex])
            w.marks.append(NSRange(location: span.range.location, length: 1))
            w.marks.append(NSRange(location: NSMaxRange(span.range) - 1, length: 1))
        }
        for block in math.blocks {
            for n in block.lines {
                w.set(
                    Self.withBreak(lines[n], in: storage), [Self.mono: true, .foregroundColor: accent.inkNative, .noteMathBlock: block.tex])
                if let syntax = block.syntax { w.set(Self.withBreak(lines[n], in: storage), [.noteMathSyntax: syntax.rawValue]) }
            }
        }

        for r in w.marks {
            storage.addAttributes([.foregroundColor: NoteLook.text3, Self.mark: true], range: r)
        }
        resolveFonts(storage, all)
        NoteLines.fix(storage)
        storage.endEditing()
        return storage
    }

    private func resolveFonts(_ storage: NSMutableAttributedString, _ all: NSRange) {
        let keys = [Self.heading, Self.weight, Self.italic, Self.mono, Self.mark]
        storage.enumerateAttributes(in: all) { attributes, range, _ in
            let marked = attributes[Self.mark] != nil
            let level = attributes[Self.heading] as? Int
            var weight = level.map { NoteLook.headingWeights[$0 - 1].rawValue } ?? PlatformFont.Weight.regular.rawValue
            if let w = attributes[Self.weight] as? CGFloat { weight = max(weight, w) }
            if marked { weight = PlatformFont.Weight.regular.rawValue }
            let size = level.map { NoteLook.headingSizes[$0 - 1] } ?? NoteLook.body
            let mono = attributes[Self.mono] != nil
            let font = NoteLook.font(
                mono ? size * NoteLook.monoScale : size, PlatformFont.Weight(weight), italic: attributes[Self.italic] != nil && !marked,
                mono: mono)
            storage.addAttribute(.font, value: font, range: range)
        }
        for key in keys { storage.removeAttribute(key, range: all) }
    }

    static func paragraph() -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = NoteLook.lineSpacing
        p.lineBreakStrategy = .hangulWordPriority
        return p
    }

    static let escape = try! NSRegularExpression(pattern: #"\\[!-/:-@\[-`{-~]"#)

    static func lines(_ text: String) -> [NSRange] {
        let ns = text as NSString
        var out: [NSRange] = []
        var start = 0
        while true {
            let r = ns.range(of: "\n", range: NSRange(location: start, length: ns.length - start))
            if r.location == NSNotFound {
                out.append(NSRange(location: start, length: ns.length - start))
                return out
            }
            out.append(NSRange(location: start, length: r.location - start))
            start = r.location + 1
        }
    }

    static func withBreak(_ line: NSRange, in storage: NSMutableAttributedString) -> NSRange {
        NSRange(location: line.location, length: min(line.length + 1, storage.length - line.location))
    }

    static func nsRange(_ r: Range<String.Index>, in s: String, at offset: Int) -> NSRange {
        let n = NSRange(r, in: s)
        return NSRange(location: n.location + offset, length: n.length)
    }

    @MainActor fileprivate struct Writer {
        let storage: NSMutableAttributedString
        let columns: Columns
        let text: NSString
        var marks: [NSRange] = []
        var code: [NSRange] = []

        func range(_ node: Markup) -> NSRange? {
            guard let r = node.range else { return nil }
            let a = columns.offset(r.lowerBound), b = columns.offset(r.upperBound)
            return b >= a ? NSRange(location: a, length: b - a) : nil
        }

        func set(_ range: NSRange, _ attributes: [NSAttributedString.Key: Any]) {
            guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
            storage.addAttributes(attributes, range: range)
        }

        var tables: [NSRange] = []

        func inCode(_ r: NSRange, orTable: Bool = true) -> Bool {
            (orTable ? code + tables : code).contains { NSIntersectionRange($0, r).length > 0 }
        }

        func lineRanges(_ r: NSRange) -> [NSRange] {
            var out: [NSRange] = []
            text.enumerateSubstrings(in: text.lineRange(for: r), options: [.byLines, .substringNotRequired]) { _, line, _, _ in
                out.append(line)
            }
            return out
        }

        mutating func walk(_ node: Markup, styler: SourceStyler) {
            styler.visit(node, &self)
            for child in node.children { walk(child, styler: styler) }
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func visit(_ node: Markup, _ w: inout Writer) {
        guard let r = w.range(node) else { return }
        let s = w.text.substring(with: r)
        switch node {
        case let h as Heading:
            w.set(r, [Self.heading: h.level] as [NSAttributedString.Key: Any])
            if h.level == 6 { w.set(r, [.foregroundColor: NoteLook.text2]) }
            if let m = s.firstMatch(of: #/^ {0,3}#{1,6}/#) { w.marks.append(Self.nsRange(m.range, in: s, at: r.location)) }
            if let m = s.firstMatch(of: /\n[=-]+\s*$/) { w.marks.append(Self.nsRange(m.range, in: s, at: r.location)) }
        case is Emphasis:
            w.set(r, [Self.italic: true])
            dim(ends: 1, r, &w)
        case is Strong:
            w.set(r, [Self.weight: PlatformFont.Weight.semibold.rawValue])
            dim(ends: 2, r, &w)
        case is Strikethrough:
            w.set(r, [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: NoteLook.text3])
            dim(ends: s.prefix { $0 == "~" }.count, r, &w)
        case is InlineCode:
            w.code.append(r)
            w.set(r, [Self.mono: true])
            dim(ends: s.prefix { $0 == "`" }.count, r, &w)
        case let link as Markdown.Link:
            let href = link.destination ?? ""
            w.set(
                r,
                [
                    .foregroundColor: accent.inkNative, .noteHref: href, .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: accent.native.withAlphaComponent(0.4),
                ])
            if s.hasPrefix("[") {
                let parts = Array(link.children).compactMap { w.range($0) }
                let label = parts.dropFirst().reduce(parts.first) { acc, r in acc.map { NSUnionRange($0, r) } }
                let end = label.map(NSMaxRange) ?? r.location + 1
                w.marks.append(NSRange(location: r.location, length: 1))
                w.marks.append(NSRange(location: end, length: NSMaxRange(r) - end))
            }
        case is Markdown.Image:
            w.set(r, [.foregroundColor: NoteLook.text3, Self.mono: true])
            if let source = (node as? Markdown.Image)?.source { w.set(r, [.noteImage: source]) }
        case let item as ListItem:
            let line = w.text.lineRange(for: NSRange(location: r.location, length: 0))
            let rest = w.text.substring(with: NSRange(location: r.location, length: NSMaxRange(line) - r.location))
            guard let m = rest.firstMatch(of: #/^([-*+]|\d+[.)])(\s+)(\[[ xX]\])?/#) else { break }
            w.set(
                NSRange(location: r.location, length: m.1.utf16.count),
                [.foregroundColor: accent.native.withAlphaComponent(0.85), Self.weight: PlatformFont.Weight.semibold.rawValue])
            if let box = m.3 {
                let at = r.location + m.1.utf16.count + m.2.utf16.count
                let done = box != "[ ]"
                w.set(
                    NSRange(location: at, length: box.utf16.count),
                    [.foregroundColor: NoteLook.text3, Self.mono: true, .noteTask: done])
                if done, let p = item.child(at: 0).flatMap(w.range) {
                    let from = at + box.utf16.count
                    w.set(
                        NSRange(location: from, length: NSMaxRange(p) - from),
                        [.foregroundColor: NoteLook.text3, .strikethroughStyle: NSUnderlineStyle.single.rawValue])
                }
            }
        case let quote as BlockQuote:
            let header = quote.calloutHeader
            let lines = w.lineRanges(r)
            for line in lines {
                if header == nil { w.set(line, [.foregroundColor: NoteLook.text2]) }
                let s = w.text.substring(with: line)
                if let m = s.firstMatch(of: #/^[ \t]*(?:>[ \t]?)+/#) { w.marks.append(Self.nsRange(m.range, in: s, at: line.location)) }
            }
            if let header, let first = lines.first {
                let s = w.text.substring(with: first)
                if let m = s.firstMatch(of: /\[![A-Za-z-]+\][+-]?/) {
                    let type = Self.nsRange(m.range, in: s, at: first.location)
                    let color = NoteLook.callout(header.type)
                    w.set(type, [Self.weight: PlatformFont.Weight.bold.rawValue, .foregroundColor: color])
                    w.set(
                        NSRange(location: NSMaxRange(type), length: NSMaxRange(first) - NSMaxRange(type)),
                        [Self.weight: PlatformFont.Weight.semibold.rawValue])
                }
            }
        case let block as CodeBlock:
            w.code.append(r)
            let lines = w.lineRanges(r)
            for line in lines {
                w.set(Self.withBreak(line, in: w.storage), [.noteCode: true, Self.mono: true])
            }
            guard let first = lines.first, let last = lines.last else { break }
            w.marks.append(first)
            if lines.count > 1,
                w.text.substring(with: last).trimmingCharacters(in: .whitespaces).hasPrefix(
                    String(w.text.substring(with: first).trimmingCharacters(in: .whitespaces).prefix(3)))
            {
                w.marks.append(last)
            }
            if let language = block.language, MathFence.syntax(language) == nil, lines.count > 2 {
                let body = NSRange(location: lines[1].location, length: NSMaxRange(lines[lines.count - 2]) - lines[1].location)
                for token in NoteScripts.highlight(w.text.substring(with: body), language: language) {
                    guard let look = NoteLook.token(token.classes) else { continue }
                    let at = NSRange(location: body.location + token.range.location, length: token.range.length)
                    w.set(at, look.italic ? [.foregroundColor: look.color, Self.italic: true] : [.foregroundColor: look.color])
                }
            }
        case is Markdown.Table:
            w.tables.append(r)
            for line in w.lineRanges(r) { w.set(line, [Self.mono: true]) }
        case is ThematicBreak:
            w.marks.append(r)
        default:
            break
        }
    }

    private func dim(ends n: Int, _ r: NSRange, _ w: inout Writer) {
        guard n > 0, r.length >= 2 * n else { return }
        w.marks.append(NSRange(location: r.location, length: n))
        w.marks.append(NSRange(location: NSMaxRange(r) - n, length: n))
    }
}

// swift-markdown의 원문 위치는 줄과 UTF-8 바이트 단위의 열이므로 UTF-16 오프셋으로 바꾼다.
private struct Columns {
    let lines: [Substring]
    let starts: [Int]

    init(_ text: String) {
        lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var at = 0
        var starts: [Int] = []
        for line in lines {
            starts.append(at)
            at += line.utf16.count + 1
        }
        self.starts = starts
    }

    func offset(_ location: SourceLocation) -> Int {
        let i = min(max(location.line - 1, 0), lines.count - 1)
        let line = lines[i]
        let bytes = min(max(location.column - 1, 0), line.utf8.count)
        let index = line.utf8.index(line.startIndex, offsetBy: bytes)
        return starts[i] + line.utf16.distance(from: line.startIndex, to: index)
    }
}
