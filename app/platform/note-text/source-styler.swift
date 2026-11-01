import FolioDomain
import FolioMarkdown
import Markdown
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension NSAttributedString.Key {
    /// A link's destination, opened on ⌘-click.
    static let noteHref = NSAttributedString.Key("folio.href")
    /// A wikilink's target note, opened on ⌘-click.
    static let noteWiki = NSAttributedString.Key("folio.wiki")
    /// A task's box, ticked by a click: `[ ]` in the source, the checkbox in the read view. The value is whether it's done.
    static let noteTask = NSAttributedString.Key("folio.task")
    /// Inline math's TeX, on its whole `$…$`, for the bubble that shows it rendered.
    static let noteMath = NSAttributedString.Key("folio.math")
    /// Lines of a fenced code block, where Enter is only a line break.
    static let noteCode = NSAttributedString.Key("folio.code")
}

/// Styles the note's markdown source in place: marks stay in the text, dimmed, and the text after them takes fonts,
/// weights, colors and tints, never spacing, so every line starts at the same x and the caret walks the raw text
/// (docs/SPEC.md "편집 방식"). Rendered math and images are drawn under their line by `NoteFragment`.
@MainActor struct SourceStyler {
    var accent: CourseAccent
    var syntax: MathSyntax
    var baseURL: URL?
    var dark: Bool
    var width: CGFloat

    // Font parts, resolved into one font per run at the end, since a run can be bold, in a heading and dimmed at once.
    private static let heading = NSAttributedString.Key("folio.s.heading")
    private static let weight = NSAttributedString.Key("folio.s.weight")
    private static let italic = NSAttributedString.Key("folio.s.italic")
    private static let mono = NSAttributedString.Key("folio.s.mono")
    private static let mark = NSAttributedString.Key("folio.s.mark")

    /// Styles the text apart and sets only the paragraphs that came out different: setting all of it would make
    /// TextKit throw away the layout of the whole note on every key, and guess again at the heights above the screen.
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
        let masked = DraftItem.mask(math.masked(text))
        let document = Document(parsing: masked)
        var w = Writer(storage: storage, columns: Columns(masked), text: text as NSString)

        storage.beginEditing()
        storage.setAttributes([.foregroundColor: NoteLook.text, .paragraphStyle: Self.paragraph()], range: all)
        w.walk(document, styler: self)
        for i in DraftItem.dashes(in: text) {
            w.set(NSRange(location: i, length: 1), [.foregroundColor: accent.native.withAlphaComponent(0.85), Self.weight: PlatformFont.Weight.semibold.rawValue])
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
            guard !w.inCode(r), !math.covers(r) else { continue }
            let open = m.1.isEmpty ? 2 : 3
            w.set(r, [.foregroundColor: accent.inkNative, Self.weight: PlatformFont.Weight.medium.rawValue,
                      .noteWiki: WikiLink(m).target, .underlineStyle: NSUnderlineStyle.single.rawValue,
                      .underlineColor: accent.native.withAlphaComponent(0.4)])
            w.marks.append(NSRange(location: r.location, length: open))
            w.marks.append(NSRange(location: NSMaxRange(r) - 2, length: 2))
        }

        for span in math.inline {
            w.set(span.range, [Self.mono: true, .foregroundColor: accent.inkNative, .noteMath: span.tex])
            w.marks.append(NSRange(location: span.range.location, length: 1))
            w.marks.append(NSRange(location: NSMaxRange(span.range) - 1, length: 1))
        }
        for block in math.blocks {
            let box = NoteBox(fill: NoteLook.tint(accent.native, 0.06), first: true, last: true)
            for n in block.lines { w.set(Self.withBreak(lines[n], in: storage), [Self.mono: true, .foregroundColor: accent.inkNative, .noteBox: box]) }
            if let picture = NoteMath.picture(block.tex, syntax: syntax, display: true, size: NoteLook.body * 1.1, color: NoteLook.text, dark: dark) {
                w.below(NoteBelow(image: picture.image, size: picture.size, gap: 8), line: lines[block.lines.upperBound], storage: storage)
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
            let font = NoteLook.font(mono ? size * NoteLook.monoScale : size, PlatformFont.Weight(weight), italic: attributes[Self.italic] != nil && !marked, mono: mono)
            storage.addAttribute(.font, value: font, range: range)
        }
        for key in keys { storage.removeAttribute(key, range: all) }
    }

    static func paragraph(spacing: CGFloat = 0) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = NoteLook.lineSpacing
        p.paragraphSpacing = spacing
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

    /// The line with its line break, which carries the paragraph's attributes.
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

        func inCode(_ r: NSRange) -> Bool { code.contains { NSIntersectionRange($0, r).length > 0 } }

        func lineRanges(_ r: NSRange) -> [NSRange] {
            var out: [NSRange] = []
            text.enumerateSubstrings(in: text.lineRange(for: r), options: [.byLines, .substringNotRequired]) { _, line, _, _ in out.append(line) }
            return out
        }

        func below(_ item: NoteBelow, line: NSRange, storage: NSMutableAttributedString) {
            let r = SourceStyler.withBreak(line, in: storage)
            guard r.length > 0 else { return }
            storage.addAttributes([.noteBelow: item, .paragraphStyle: SourceStyler.paragraph(spacing: item.room)], range: r)
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
            if h.level >= 4 { w.set(r, [.foregroundColor: NoteLook.text2]) }
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
            w.set(r, [Self.mono: true, .backgroundColor: NoteLook.fill])
            dim(ends: s.prefix { $0 == "`" }.count, r, &w)
        case let link as Markdown.Link:
            let href = link.destination ?? ""
            w.set(r, [.foregroundColor: accent.inkNative, .noteHref: href, .underlineStyle: NSUnderlineStyle.single.rawValue,
                      .underlineColor: accent.native.withAlphaComponent(0.4)])
            if s.hasPrefix("[") {
                let parts = Array(link.children).compactMap { w.range($0) }
                let label = parts.dropFirst().reduce(parts.first) { acc, r in acc.map { NSUnionRange($0, r) } }
                let end = label.map(NSMaxRange) ?? r.location + 1
                w.marks.append(NSRange(location: r.location, length: 1))
                w.marks.append(NSRange(location: end, length: NSMaxRange(r) - end))
            }
        case is Markdown.Image:
            w.set(r, [.foregroundColor: NoteLook.text3, Self.mono: true])
            if let image = node as? Markdown.Image, let item = picture(image), let line = w.lineRanges(r).last {
                w.below(item, line: line, storage: w.storage)
            }
        case let item as ListItem:
            let line = w.text.lineRange(for: NSRange(location: r.location, length: 0))
            let rest = w.text.substring(with: NSRange(location: r.location, length: NSMaxRange(line) - r.location))
            guard let m = rest.firstMatch(of: #/^([-*+]|\d+[.)])(\s+)(\[[ xX]\])?/#) else { break }
            w.set(NSRange(location: r.location, length: m.1.utf16.count),
                  [.foregroundColor: accent.native.withAlphaComponent(0.85), Self.weight: PlatformFont.Weight.semibold.rawValue])
            if let box = m.3 {
                let at = r.location + m.1.utf16.count + m.2.utf16.count
                let done = box != "[ ]"
                w.set(NSRange(location: at, length: box.utf16.count),
                      [.foregroundColor: NoteLook.text3, Self.mono: true, .noteTask: done])
                if done, let p = item.child(at: 0).flatMap(w.range) {
                    let from = at + box.utf16.count
                    w.set(NSRange(location: from, length: NSMaxRange(p) - from),
                          [.foregroundColor: NoteLook.text3, .strikethroughStyle: NSUnderlineStyle.single.rawValue])
                }
            }
        case let quote as BlockQuote:
            let header = quote.calloutHeader
            let lines = w.lineRanges(r)
            let box = header.flatMap { h -> NoteBox? in
                let kind = NoteLook.callout(h.type)
                return kind.tinted ? NoteBox(fill: NoteLook.tint(kind.color, NoteLook.tint), first: true, last: true) : nil
            }
            for line in lines {
                if header == nil { w.set(line, [.foregroundColor: NoteLook.text2]) }
                if let box { w.set(Self.withBreak(line, in: w.storage), [.noteBox: box]) }
                let s = w.text.substring(with: line)
                if let m = s.firstMatch(of: #/^[ \t]*(?:>[ \t]?)+/#) { w.marks.append(Self.nsRange(m.range, in: s, at: line.location)) }
            }
            if let header, let first = lines.first {
                let s = w.text.substring(with: first)
                if let m = s.firstMatch(of: /\[![A-Za-z-]+\][+-]?/) {
                    let type = Self.nsRange(m.range, in: s, at: first.location)
                    let color = NoteLook.callout(header.type).color
                    w.set(type, [Self.weight: PlatformFont.Weight.bold.rawValue, .foregroundColor: color])
                    w.set(NSRange(location: NSMaxRange(type), length: NSMaxRange(first) - NSMaxRange(type)), [Self.weight: PlatformFont.Weight.semibold.rawValue])
                }
            }
        case let block as CodeBlock:
            w.code.append(r)
            let lines = w.lineRanges(r)
            let box = NoteBox(fill: NoteLook.fill, first: true, last: true)
            for line in lines {
                w.set(Self.withBreak(line, in: w.storage), [.noteBox: box, .noteCode: true, Self.mono: true])
            }
            guard let first = lines.first, let last = lines.last else { break }
            w.marks.append(first)
            if lines.count > 1, w.text.substring(with: last).trimmingCharacters(in: .whitespaces).hasPrefix(String(w.text.substring(with: first).trimmingCharacters(in: .whitespaces).prefix(3))) {
                w.marks.append(last)
            }
            if let language = block.language, lines.count > 2 {
                let body = NSRange(location: lines[1].location, length: NSMaxRange(lines[lines.count - 2]) - lines[1].location)
                for token in NoteScripts.highlight(w.text.substring(with: body), language: language) {
                    guard let look = NoteLook.token(token.classes) else { continue }
                    let at = NSRange(location: body.location + token.range.location, length: token.range.length)
                    w.set(at, look.italic ? [.foregroundColor: look.color, Self.italic: true] : [.foregroundColor: look.color])
                }
            }
        case is Markdown.Table:
            w.code.append(r)
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

    private func picture(_ image: Markdown.Image) -> NoteBelow? {
        guard let source = image.source, let picture = NoteImages.load(source, base: baseURL) else { return nil }
        let size = NoteImages.fit(picture.size, alt: image.plainText, width: width)
        return NoteBelow(image: picture, size: size, gap: 6)
    }
}

/// Converts swift-markdown's source locations (lines, and columns in UTF-8 bytes) to UTF-16 offsets.
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

/// Where math is in the source, read as `MathProtection` reads it, so the source and the read view agree.
struct MathScan {
    struct Inline { let range: NSRange; let tex: String }
    struct Block { let lines: ClosedRange<Int>; let tex: String; let ranges: [NSRange] }

    var inline: [Inline] = []
    var blocks: [Block] = []

    init(text: String, lines: [NSRange]) {
        let ns = text as NSString
        var fence: String?
        var i = 0
        while i < lines.count {
            let line = ns.substring(with: lines[i])
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            defer { i += 1 }
            if let open = fence {
                if trimmed.hasPrefix(open) { fence = nil }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                continue
            }
            let prefix = line.prefix { $0 == " " || $0 == ">" }.utf16.count
            if (line as NSString).substring(from: prefix).hasPrefix("$$") {
                let first = i
                var body = (line as NSString).substring(from: prefix + 2).trimmingCharacters(in: .whitespaces)
                var ranges = [NSRange(location: lines[i].location + prefix, length: lines[i].length - prefix)]
                while !body.hasSuffix("$$"), i + 1 < lines.count {
                    i += 1
                    let next = ns.substring(with: lines[i])
                    let cut = min(prefix, next.prefix { $0 == " " || $0 == ">" }.utf16.count)
                    body += "\n" + (next as NSString).substring(from: cut)
                    ranges.append(NSRange(location: lines[i].location + cut, length: lines[i].length - cut))
                }
                if body.hasSuffix("$$") { body.removeLast(2) }
                blocks.append(Block(lines: first...i, tex: body.trimmingCharacters(in: .whitespacesAndNewlines), ranges: ranges))
                continue
            }
            scanInline(line, at: lines[i].location)
        }
    }

    private mutating func scanInline(_ line: String, at offset: Int) {
        let chars = Array(line.utf16)
        var k = 0
        while k < chars.count {
            let c = chars[k]
            if c == 0x5C, k + 1 < chars.count, chars[k + 1] == 0x24 { k += 2; continue }
            if c == 0x60 {
                var n = 0
                while k + n < chars.count, chars[k + n] == 0x60 { n += 1 }
                var j = k + n
                var closed = false
                while j + n <= chars.count {
                    if chars[j..<(j + n)].allSatisfy({ $0 == 0x60 }) { closed = true; break }
                    j += 1
                }
                k = closed ? j + n : k + n
                continue
            }
            if c == 0x24 {
                var j = k + 1
                while j < chars.count, !(chars[j] == 0x24 && chars[j - 1] != 0x5C) { j += 1 }
                if j < chars.count, j > k + 1, chars[k + 1] != 0x20, chars[j - 1] != 0x20 {
                    let tex = String(utf16CodeUnits: Array(chars[(k + 1)..<j]), count: j - k - 1)
                    inline.append(Inline(range: NSRange(location: offset + k, length: j - k + 1), tex: tex))
                    k = j + 1
                    continue
                }
            }
            k += 1
        }
    }

    /// The text with math blanked out (same length), so the markdown parser reads no emphasis or escapes inside TeX.
    func masked(_ text: String) -> String {
        let out = NSMutableString(string: text)
        for r in inline.map(\.range) + blocks.flatMap(\.ranges) {
            out.replaceCharacters(in: r, with: String(repeating: "x", count: r.length))
        }
        return out as String
    }

    func covers(_ r: NSRange) -> Bool {
        (inline.map(\.range) + blocks.flatMap(\.ranges)).contains { NSIntersectionRange($0, r).length > 0 }
    }
}

/// Note pictures from `Notes/assets`, read once per file and size.
@MainActor enum NoteImages {
    private static var cache: [URL: (date: Date?, image: PlatformImage)] = [:]

    static func url(_ source: String, base: URL?) -> URL? {
        let decoded = source.removingPercentEncoding ?? source
        guard !decoded.hasPrefix("http"), let base else { return nil }
        return decoded.hasPrefix("/") ? URL(filePath: decoded) : base.appending(path: decoded)
    }

    static func load(_ source: String, base: URL?) -> PlatformImage? {
        guard let url = url(source, base: base) else { return nil }
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let hit = cache[url], hit.date == date { return hit.image }
        #if os(macOS)
        guard let image = NSImage(contentsOf: url) else { return nil }
        #else
        guard let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) else { return nil }
        #endif
        cache[url] = (date, image)
        return image
    }

    /// Obsidian's `![alt|300](src)` caps the width; without it the picture takes the column, never more.
    static func fit(_ natural: CGSize, alt: String, width: CGFloat) -> CGSize {
        let asked = alt.firstMatch(of: /\|\s*(\d+)(?:x\d+)?\s*$/).flatMap { CGFloat(Int($0.1) ?? 0) }
        let w = min(asked ?? natural.width, width)
        guard natural.width > 0 else { return .zero }
        return CGSize(width: w, height: natural.height * w / natural.width)
    }
}
