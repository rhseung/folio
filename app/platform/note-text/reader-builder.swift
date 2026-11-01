import FolioDomain
import FolioMarkdown
import Markdown
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension NSAttributedString.Key {
    /// The index of the top-level block a character belongs to, its line break included.
    static let noteBlock = NSAttributedString.Key("folio.block")
    /// `NoteAtom`: drawn text or a picture standing for markdown that is written back whole (math, wikilinks, images,
    /// list markers). Typing never goes inside one.
    static let noteAtom = NSAttributedString.Key("folio.atom")
    /// `ListInfo` on a list item's paragraph.
    static let noteListItem = NSAttributedString.Key("folio.list-item")
    /// `InlineMarks` raw value: the emphasis the text is written with.
    static let noteMarks = NSAttributedString.Key("folio.marks")
    /// A markdown link's destination, on its label.
    static let noteLink = NSAttributedString.Key("folio.link")
    /// The index of a callout whose header folds it on a click.
    static let noteCallout = NSAttributedString.Key("folio.callout")
}

struct InlineMarks: OptionSet {
    let rawValue: Int
    static let strong = InlineMarks(rawValue: 1)
    static let emphasis = InlineMarks(rawValue: 2)
    static let strike = InlineMarks(rawValue: 4)
    static let code = InlineMarks(rawValue: 8)
}

final class NoteAtom: NSObject, @unchecked Sendable {
    let source: String
    init(_ source: String) { self.source = source }
}

final class ListInfo: NSObject, @unchecked Sendable {
    let depth: Int
    let ordered: Bool
    /// The number shown; a nested list starts from its first item's.
    let number: Int
    let task: Bool
    let id: String?

    init(depth: Int, ordered: Bool, number: Int, task: Bool, id: String? = nil) {
        self.depth = depth
        self.ordered = ordered
        self.number = number
        self.task = task
        self.id = id
    }
}

/// A top-level block of the rendered note and the body lines it was written on.
struct ReaderBlock {
    enum Kind: Equatable { case paragraph, heading(Int), list, other }
    var kind: Kind
    var lines: ClosedRange<Int>
    var source: String
    var id: String?
    var editable = false
}

/// Renders a note for the read view as one attributed string: text where the note is text, pictures for math, images
/// and tables, and box tints for quotes, callouts and code (`NoteFragment`).
@MainActor struct ReaderBuilder {
    var accent: CourseAccent
    var syntax: MathSyntax
    var baseURL: URL?
    var dark: Bool
    var width: CGFloat
    /// Callouts folded or unfolded by a click, against how the note starts them.
    var toggled: Set<Int> = []

    private var out = NSMutableAttributedString()
    private var calloutCount = 0
    private var counters: [String: Int] = [:]
    /// The block ID taken off the last paragraph.
    private var lastID: String?

    init(accent: CourseAccent, syntax: MathSyntax, baseURL: URL?, dark: Bool, width: CGFloat, toggled: Set<Int> = []) {
        self.accent = accent
        self.syntax = syntax
        self.baseURL = baseURL
        self.dark = dark
        self.width = width
        self.toggled = toggled
    }

    struct Context {
        var indent: CGFloat = 0
        var color = NoteLook.text
        var depth = 0
        /// Inside a quote or callout, whose box a nested quote can't replace.
        var boxed = false
    }

    mutating func build(_ note: ParsedNote) -> (text: NSAttributedString, blocks: [ReaderBlock]) {
        out = NSMutableAttributedString()
        calloutCount = 0
        counters = [:]
        var blocks: [ReaderBlock] = []
        let children = Array(note.document.children)
        var previousCallout: String?
        for (i, node) in children.enumerated() {
            let start = out.length
            lastID = nil
            let header = (node as? BlockQuote)?.calloutHeader
            let nextHeader = i + 1 < children.count ? (children[i + 1] as? BlockQuote)?.calloutHeader : nil
            var kind = ReaderBlock.Kind.other
            switch node {
            case let quote as BlockQuote where header != nil:
                let attached = header!.type == "proof" && CalloutHeader.provable.contains(previousCallout ?? "")
                let joinsBelow = nextHeader?.type == "proof" && CalloutHeader.provable.contains(header!.type)
                callout(quote, header!, Context(), attached: attached, joinsBelow: joinsBelow)
            case is Paragraph:
                kind = .paragraph
                block(node, Context())
            case let h as Heading:
                kind = .heading(h.level)
                block(node, Context())
            case is UnorderedList, is OrderedList:
                kind = .list
                block(node, Context())
            default:
                block(node, Context())
            }
            previousCallout = header?.type
            guard let lines = note.lines(of: node) else { continue }
            let range = NSRange(location: start, length: out.length - start)
            out.addAttribute(.noteBlock, value: blocks.count, range: range)
            blocks.append(ReaderBlock(kind: kind, lines: lines, source: note.source(lines), id: kind == .paragraph ? lastID : nil))
        }
        if out.string.hasSuffix("\n") { out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1)) }
        NoteLines.fix(out)
        for i in blocks.indices where blocks[i].kind != .other {
            guard let range = Self.range(of: i, in: out) else { continue }
            let written = ReaderMarkdown.block(out, range, kind: blocks[i].kind, source: blocks[i].source, id: blocks[i].id)
            blocks[i].editable = written == blocks[i].source
        }
        return (out, blocks)
    }

    /// The block's characters without its closing line break.
    static func range(of block: Int, in text: NSAttributedString) -> NSRange? {
        var found: NSRange?
        text.enumerateAttribute(.noteBlock, in: NSRange(location: 0, length: text.length)) { value, r, stop in
            guard value as? Int == block else { return }
            found = found.map { NSUnionRange($0, r) } ?? r
            if found != nil, (value as? Int) != block { stop.pointee = true }
        }
        guard var r = found else { return nil }
        if r.length > 0, (text.string as NSString).character(at: NSMaxRange(r) - 1) == 0x0A { r.length -= 1 }
        return r
    }

    // MARK: Paragraph styles

    static func paragraph(_ ctx: Context, before: CGFloat = 0, after: CGFloat = NoteLook.paragraphGap, lineSpacing: CGFloat = NoteLook.lineSpacing,
                          alignment: NSTextAlignment = .natural, head: CGFloat = 0) -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = lineSpacing
        p.paragraphSpacingBefore = before
        p.paragraphSpacing = after
        p.alignment = alignment
        p.firstLineHeadIndent = ctx.indent
        p.headIndent = ctx.indent + head
        p.tailIndent = ctx.indent > 0 ? -ctx.indent : 0
        p.lineBreakStrategy = .hangulWordPriority
        return p
    }

    private func attributes(_ ctx: Context, _ style: NSParagraphStyle, font: PlatformFont = NoteLook.font(NoteLook.body)) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: ctx.color, .paragraphStyle: style]
    }

    private mutating func newline(_ attributes: [NSAttributedString.Key: Any]) {
        out.append(NSAttributedString(string: "\n", attributes: attributes))
    }

    /// Changes the spacing of the paragraphs in `range`.
    private func respace(_ range: NSRange, _ change: (NSMutableParagraphStyle) -> Void) {
        out.enumerateAttribute(.paragraphStyle, in: range) { value, r, _ in
            guard let p = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle else { return }
            change(p)
            out.addAttribute(.paragraphStyle, value: p, range: r)
        }
    }

    private func paragraphs(in range: NSRange) -> [NSRange] {
        var list: [NSRange] = []
        (out.string as NSString).enumerateSubstrings(in: range, options: [.byParagraphs, .substringNotRequired]) { _, _, enclosing, _ in list.append(enclosing) }
        return list
    }

    // MARK: Blocks

    private mutating func block(_ node: Markup, _ ctx: Context) {
        switch node {
        case let p as Paragraph:
            paragraph(Array(p.inlineChildren), ctx)
        case let h as Heading:
            let level = h.level
            let size = NoteLook.headingSizes[level - 1]
            let first = out.length == 0
            let before: CGFloat = first ? 0 : [12, 36, 24, 20, 20, 20][level - 1]
            let after: CGFloat = [24, 22, 8, 6, 6, 6][level - 1]
            let style = Self.paragraph(ctx, before: before, after: after, lineSpacing: 4)
            var c = ctx
            if level >= 4 { c.color = NoteLook.text2 }
            let start = out.length
            inlines(Array(h.inlineChildren), Inline(size: size, weight: NoteLook.headingWeights[level - 1], color: c.color), style: style)
            let a = attributes(c, style, font: NoteLook.font(size, NoteLook.headingWeights[level - 1]))
            newline(a)
            if level == 2 { out.addAttribute(.noteRule, value: NoteLook.lineSoft, range: NSRange(location: start, length: out.length - start)) }
        case let quote as BlockQuote:
            if let header = quote.calloutHeader {
                callout(quote, header, ctx, attached: false, joinsBelow: false)
                return
            }
            var c = ctx
            c.indent += NoteLook.boxIndent
            c.color = NoteLook.text2
            c.boxed = true
            let start = out.length
            for child in quote.children { block(child, c) }
            let range = NSRange(location: start, length: out.length - start)
            if ctx.boxed {
                // A paragraph holds one box, so a quote inside another adds a spine to the outer box rather than a box of its own.
                let list = paragraphs(in: range)
                for p in list {
                    let inner = out.attribute(.noteQuotes, at: p.location, effectiveRange: nil) as? [NoteBox] ?? []
                    out.addAttribute(.noteQuotes, value: [NoteBox(fill: nil, spine: NoteLook.line, first: p == list.first, last: p == list.last)] + inner, range: p)
                }
            } else {
                box(range, NoteBox(fill: nil, spine: NoteLook.line, first: true, last: true), gap: NoteLook.blockGap * 0.8, padding: 2)
            }
        case let block as CodeBlock:
            code(block, ctx)
        case let list as UnorderedList:
            listItems(Array(list.listItems), ordered: false, start: 1, ctx)
        case let list as OrderedList:
            listItems(Array(list.listItems), ordered: true, start: Int(list.startIndex), ctx)
        case let table as Markdown.Table:
            let image = ReaderTable.render(table, builder: self)
            picture(image, ctx)
        case is ThematicBreak:
            let style = Self.paragraph(ctx, before: 16, after: 28, alignment: .center)
            out.append(NSAttributedString(string: "· · ·", attributes: attributes(ctx, style, font: NoteLook.font(14)).merging([.foregroundColor: NoteLook.text3, .kern: 6]) { $1 }))
            newline(attributes(ctx, style))
        case let html as HTMLBlock:
            let style = Self.paragraph(ctx)
            let text = html.rawHTML.trimmingCharacters(in: .newlines).replacingOccurrences(of: "\n", with: "\u{2028}")
            out.append(NSAttributedString(string: text, attributes: attributes(ctx, style, font: NoteLook.font(NoteLook.codeSize, mono: true)).merging([.foregroundColor: NoteLook.text3]) { $1 }))
            newline(attributes(ctx, style))
        default:
            for child in node.children { self.block(child, ctx) }
        }
    }

    private mutating func paragraph(_ inlineNodes: [Markup], _ ctx: Context, style: NSParagraphStyle? = nil) {
        let style = style ?? Self.paragraph(ctx)
        // A picture alone in its paragraph stands centered on the page.
        if inlineNodes.count == 1, inlineNodes[0] is Markdown.Image {
            let centered = (style.mutableCopy() as! NSMutableParagraphStyle)
            centered.alignment = .center
            centered.paragraphSpacingBefore = 8
            centered.paragraphSpacing = NoteLook.blockGap
            inlines(inlineNodes, Inline(color: ctx.color), style: centered)
            newline(attributes(ctx, centered))
            return
        }
        let at = out.length
        inlines(inlineNodes, Inline(color: ctx.color), style: style)
        lastID = stripBlockID(from: at)
        newline(attributes(ctx, style))
    }

    private mutating func listItems(_ items: [ListItem], ordered: Bool, start: Int, _ ctx: Context) {
        let begin = out.length
        let marker = NoteLook.font(NoteLook.body, .semibold)
        let markerWidth: CGFloat = ordered ? 26 : 18
        for (i, item) in items.enumerated() {
            var c = ctx
            let first = item.child(at: 0) as? Paragraph
            // `- [ ]` with nothing after isn't a task in GFM, but Obsidian draws and ticks its box.
            let bare = item.checkbox == nil ? first.flatMap(Self.bareBox) : nil
            let checkbox = item.checkbox ?? bare
            let task = checkbox != nil
            let style = Self.paragraph(ctx, after: 4, head: markerWidth + (task ? 24 : 0))
            style.tabStops = [NSTextTab(textAlignment: .left, location: ctx.indent + markerWidth)]
            style.defaultTabInterval = 24
            let number = start + i
            let itemStart = out.length
            // A marker (and checkbox) is drawn, not typed; it's written back from the item's `ListInfo`.
            let mark = ordered ? "\(number).\t" : "•\t"
            out.append(NSAttributedString(string: mark, attributes: attributes(ctx, style, font: ordered ? NoteLook.font(NoteLook.body * 0.92, .semibold) : marker)
                .merging([.foregroundColor: ordered ? NoteLook.text3 : accent.native.withAlphaComponent(0.8), .noteAtom: NoteAtom("")]) { $1 }))
            if let checkbox {
                out.append(Self.checkbox(checkbox == .checked, accent: accent, attributes: attributes(ctx, style)))
                if checkbox == .checked { c.color = NoteLook.text3 }
            }
            var id: String?
            if let first, bare == nil {
                let at = out.length
                inlines(Array(first.inlineChildren), Inline(color: c.color), style: style)
                id = stripBlockID(from: at)
                if checkbox == .checked {
                    out.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: NoteLook.text3.withAlphaComponent(0.6)],
                                      range: NSRange(location: at, length: out.length - at))
                }
            }
            newline(attributes(ctx, style))
            out.addAttribute(.noteListItem, value: ListInfo(depth: ctx.depth, ordered: ordered, number: number, task: task, id: id),
                             range: NSRange(location: itemStart, length: out.length - itemStart))
            var sub = ctx
            sub.indent += markerWidth
            sub.depth += 1
            for child in item.children.dropFirst(first == nil ? 0 : 1) { block(child, sub) }
        }
        if ctx.depth == 0, let last = paragraphs(in: NSRange(location: begin, length: out.length - begin)).last {
            respace(last) { $0.paragraphSpacing = NoteLook.paragraphGap }
        }
    }

    static func bareBox(_ p: Paragraph) -> Checkbox? {
        switch p.plainText.trimmingCharacters(in: .whitespaces) {
        case "[ ]": .unchecked
        case "[x]", "[X]": .checked
        default: nil
        }
    }

    static func chevron(_ open: Bool, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let name = open ? "chevron.down" : "chevron.right"
        #if os(macOS)
        let config = NSImage.SymbolConfiguration(pointSize: NoteLook.labelSize, weight: .semibold).applying(.init(paletteColors: [NoteLook.text3]))
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        #else
        let image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: NoteLook.labelSize, weight: .semibold))?
            .withTintColor(NoteLook.text3, renderingMode: .alwaysOriginal)
        #endif
        guard let image else { return NSAttributedString(string: open ? "⌄" : "›", attributes: attributes) }
        let font = attributes[.font] as? PlatformFont
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: ((font?.capHeight ?? image.size.height) - image.size.height) / 2, width: image.size.width, height: image.size.height)
        return NSAttributedString(attachment: attachment, attributes: attributes)
    }

    static func checkbox(_ done: Bool, accent: CourseAccent, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let size = CGSize(width: 16, height: 16)
        let image = ReaderPictures.draw(size) { context in
            let r = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let path = CGPath(roundedRect: r, cornerWidth: 4, cornerHeight: 4, transform: nil)
            context.addPath(path)
            if done {
                context.setFillColor(accent.native.cgColor)
                context.fillPath()
                context.setStrokeColor(PlatformColor.white.cgColor)
                context.setLineWidth(2)
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.move(to: CGPoint(x: 4.5, y: 8.5))
                context.addLine(to: CGPoint(x: 7, y: 11))
                context.addLine(to: CGPoint(x: 11.5, y: 5.5))
                context.strokePath()
            } else {
                context.setStrokeColor(NoteLook.text3.cgColor)
                context.setLineWidth(1.5)
                context.strokePath()
            }
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -3, width: size.width, height: size.height)
        let s = NSMutableAttributedString(attachment: attachment)
        s.append(NSAttributedString(string: "\t"))
        s.addAttributes(attributes.merging([.noteAtom: NoteAtom(""), .noteTask: done]) { $1 }, range: NSRange(location: 0, length: s.length))
        return s
    }

    private mutating func code(_ block: CodeBlock, _ ctx: Context) {
        let text = block.code.hasSuffix("\n") ? String(block.code.dropLast()) : block.code
        switch block.language {
        case MathProtection.blockLanguage:
            displayMath(text, ctx)
            return
        case CBTable.language:
            let image = ReaderTable.render(json: text, builder: self)
            picture(image, ctx)
            return
        case NoteMermaid.language:
            if let image = NoteMermaid.picture(text, accent: accent.native, dark: dark, width: width - ctx.indent * 2) {
                picture(image, ctx)
                return
            }
        case CBWidget.language:
            let height = (try? JSONDecoder().decode(CBWidget.self, from: Data(text.utf8)))?.height ?? 120
            picture(ReaderPictures.placeholder(CGSize(width: width - ctx.indent * 2, height: height)), ctx)
            return
        default:
            break
        }
        var c = ctx
        c.indent += NoteLook.boxIndent
        let start = out.length
        let font = NoteLook.font(NoteLook.codeSize, mono: true)
        if let language = block.language, !language.isEmpty {
            let label = Self.paragraph(c, after: 8, lineSpacing: 4)
            out.append(NSAttributedString(string: language.uppercased(), attributes: attributes(c, label, font: NoteLook.font(NoteLook.smallSize, .semibold))
                .merging([.foregroundColor: NoteLook.text3, .kern: 0.6]) { $1 }))
            newline(attributes(c, label))
        }
        let style = Self.paragraph(c, after: 0, lineSpacing: 6)
        let body = NSMutableAttributedString(string: text.replacingOccurrences(of: "\n", with: "\u{2028}"), attributes: attributes(c, style, font: font))
        for token in NoteScripts.highlight(text, language: block.language ?? "") {
            guard let look = NoteLook.token(token.classes), NSMaxRange(token.range) <= body.length else { continue }
            body.addAttribute(.foregroundColor, value: look.color, range: token.range)
            if look.italic { body.addAttribute(.font, value: NoteLook.font(NoteLook.codeSize, italic: true, mono: true), range: token.range) }
        }
        out.append(body)
        newline(attributes(c, style))
        box(NSRange(location: start, length: out.length - start), NoteBox(fill: NoteLook.fill, first: true, last: true, rounded: true),
            gap: NoteLook.blockGap * 0.9, padding: 16)
    }

    /// A tint behind `range`, with `padding` inside it above and below and `gap` outside.
    private func box(_ range: NSRange, _ style: NoteBox, gap: CGFloat, padding: CGFloat, joinsAbove: Bool = false, joinsBelow: Bool = false) {
        let list = paragraphs(in: range)
        guard let first = list.first, let last = list.last else { return }
        let outerTop = joinsAbove ? 0 : gap, outerBottom = joinsBelow ? 0 : gap
        for p in list {
            let isFirst = p == first, isLast = p == last
            out.addAttribute(.noteBox, value: NoteBox(fill: style.fill, spine: style.spine, first: isFirst, last: isLast,
                                                     outerTop: isFirst ? outerTop : 0, outerBottom: isLast ? outerBottom : 0,
                                                     rounded: style.rounded, joinsAbove: joinsAbove, joinsBelow: joinsBelow), range: p)
        }
        respace(first) { $0.paragraphSpacingBefore = outerTop + padding }
        respace(last) { $0.paragraphSpacing = outerBottom + padding }
    }

    private mutating func callout(_ quote: BlockQuote, _ header: CalloutHeader, _ ctx: Context, attached: Bool, joinsBelow: Bool) {
        let index = calloutCount
        calloutCount += 1
        var label = header.type.prefix(1).uppercased() + header.type.dropFirst()
        var title = header.title
        if CalloutHeader.numbered.contains(header.type) {
            if let explicit = header.explicitNumber {
                label += " " + explicit
                title = title.replacingOccurrences(of: #"^(?:[A-Za-z]+\s+)?\#(explicit)\s*"#, with: "", options: .regularExpression)
            } else {
                counters[header.type, default: 0] += 1
                label += " \(counters[header.type]!)"
            }
        }
        let open = (attached ? false : !header.folded) != toggled.contains(index)
        let kind = NoteLook.callout(header.type)
        var c = ctx
        c.indent += NoteLook.boxIndent
        c.boxed = true
        let start = out.length
        let headerStyle = Self.paragraph(c, after: open ? 6 : 0)
        headerStyle.tabStops = [NSTextTab(textAlignment: .right, location: width - c.indent - NoteLook.boxPadding)]
        out.append(NSAttributedString(string: label, attributes: attributes(c, headerStyle, font: NoteLook.font(NoteLook.labelSize, .bold)).merging([.foregroundColor: kind.color]) { $1 }))
        if !title.isEmpty {
            out.append(NSAttributedString(string: "  ", attributes: attributes(c, headerStyle)))
            if let p = Document(parsing: MathProtection.protectInline(title)).child(at: 0) as? Paragraph {
                inlines(Array(p.inlineChildren), Inline(weight: .semibold, color: c.color), style: headerStyle)
            }
        }
        out.append(NSAttributedString(string: "\t", attributes: attributes(c, headerStyle)))
        out.append(Self.chevron(open, attributes: attributes(c, headerStyle)))
        newline(attributes(c, headerStyle))
        out.addAttribute(.noteCallout, value: index, range: NSRange(location: start, length: out.length - start))
        if open, let first = quote.child(at: 0) as? Paragraph {
            let rest = Array(first.inlineChildren.drop { !($0 is SoftBreak || $0 is LineBreak) }.dropFirst())
            if !rest.isEmpty { paragraph(rest, c) }
            for child in quote.children.dropFirst() { block(child, c) }
            let bodyStart = out.length
            _ = bodyStart
            if header.type == "proof" {
                out.insert(NSAttributedString(string: "\t∎", attributes: attributes(c, headerStyle).merging([.foregroundColor: NoteLook.text3]) { $1 }),
                           at: max(start, out.length - 1))
                if let last = paragraphs(in: NSRange(location: start, length: out.length - start)).last {
                    respace(last) { $0.tabStops = headerStyle.tabStops }
                }
            }
        }
        let range = NSRange(location: start, length: out.length - start)
        respace(range) { $0.paragraphSpacing = min($0.paragraphSpacing, NoteLook.paragraphGap * 0.7) }
        box(range, NoteBox(fill: kind.tinted ? NoteLook.tint(kind.color, NoteLook.tint) : nil, spine: NoteLook.tint(kind.color, 0.75),
                           first: true, last: true, rounded: true),
            gap: NoteLook.blockGap, padding: NoteLook.boxPadding, joinsAbove: attached, joinsBelow: joinsBelow)
    }

    private mutating func displayMath(_ tex: String, _ ctx: Context) {
        let style = Self.paragraph(ctx, before: 10, after: NoteLook.blockGap, alignment: .center)
        if let picture = NoteMath.picture(tex, syntax: syntax, display: true, size: NoteLook.body * 1.1, color: NoteLook.text, dark: dark) {
            let attachment = NSTextAttachment()
            attachment.image = picture.image
            attachment.bounds = CGRect(x: 0, y: -picture.descent, width: picture.size.width, height: picture.size.height)
            out.append(NSAttributedString(attachment: attachment, attributes: attributes(ctx, style)))
        } else {
            out.append(mathError(tex, attributes(ctx, style)))
        }
        newline(attributes(ctx, style))
    }

    private mutating func picture(_ image: (image: PlatformImage, size: CGSize)?, _ ctx: Context) {
        guard let image else { return }
        let style = Self.paragraph(ctx, before: 6, after: NoteLook.blockGap)
        let attachment = NSTextAttachment()
        attachment.image = image.image
        attachment.bounds = CGRect(origin: .zero, size: image.size)
        out.append(NSAttributedString(attachment: attachment, attributes: attributes(ctx, style)))
        newline(attributes(ctx, style))
    }

    private func mathError(_ source: String, _ attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        NSAttributedString(string: source, attributes: attributes.merging([
            .font: NoteLook.font(NoteLook.body * 0.9, mono: true), .foregroundColor: NoteLook.danger,
            .backgroundColor: NoteLook.danger.withAlphaComponent(0.1),
        ]) { $1 })
    }

    /// Takes a trailing ` ^id` off the text written since `start`; the block keeps it to write back.
    private func stripBlockID(from start: Int) -> String? {
        let s = (out.string as NSString).substring(from: start)
        guard let m = s.firstMatch(of: BlockID.pattern) else { return nil }
        let r = NSRange(m.range, in: s)
        out.deleteCharacters(in: NSRange(location: start + r.location, length: r.length))
        return String(m.1)
    }

    // MARK: Inlines

    struct Inline {
        var size = NoteLook.body
        var weight = PlatformFont.Weight.regular
        var color = NoteLook.text
        var marks: InlineMarks = []
        var link: String?
    }

    mutating func inlines(_ nodes: [Markup], _ style: Inline, style paragraph: NSParagraphStyle) {
        var pending = ""
        func flush(_ builder: inout ReaderBuilder) {
            guard !pending.isEmpty else { return }
            builder.text(pending, style, paragraph)
            pending = ""
        }
        for node in nodes {
            // Adjacent text nodes are read as one: the parser splits `[[` into pieces of its own.
            if let t = node as? Markdown.Text {
                pending += t.string
                continue
            }
            flush(&self)
            inline(node, style, paragraph)
        }
        flush(&self)
    }

    private func attributes(_ s: Inline, _ paragraph: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        let code = s.marks.contains(.code)
        var weight = s.weight
        if s.marks.contains(.strong), weight.rawValue < PlatformFont.Weight.semibold.rawValue { weight = .semibold }
        var a: [NSAttributedString.Key: Any] = [
            .font: NoteLook.font(code ? s.size * 0.86 : s.size, weight, italic: s.marks.contains(.emphasis), mono: code),
            .foregroundColor: s.link != nil ? accent.inkNative : s.marks.contains(.strike) ? NoteLook.text3 : s.color,
            .paragraphStyle: paragraph, .noteMarks: s.marks.rawValue,
        ]
        if code { a[.backgroundColor] = NoteLook.fill }
        if s.marks.contains(.strike) { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if let link = s.link {
            a[.noteLink] = link
            a[.noteHref] = link
            a[.underlineStyle] = NSUnderlineStyle.single.rawValue
            a[.underlineColor] = accent.native.withAlphaComponent(0.35)
        }
        return a
    }

    private mutating func text(_ string: String, _ s: Inline, _ paragraph: NSParagraphStyle) {
        var cursor = string.startIndex
        for m in string.matches(of: WikiLink.pattern) {
            if cursor < m.range.lowerBound { out.append(NSAttributedString(string: String(string[cursor..<m.range.lowerBound]), attributes: attributes(s, paragraph))) }
            let link = WikiLink(m)
            var a = attributes(s, paragraph)
            a[.noteAtom] = NoteAtom(String(m.0))
            if link.isEmbed {
                a[.foregroundColor] = NoteLook.text3
                out.append(NSAttributedString(string: "↪ " + link.target, attributes: a))
            } else {
                a[.foregroundColor] = accent.inkNative
                a[.font] = NoteLook.font(s.size, s.marks.contains(.strong) ? .semibold : .medium, italic: s.marks.contains(.emphasis))
                a[.noteWiki] = link.target
                a[.underlineStyle] = NSUnderlineStyle.single.rawValue
                a[.underlineColor] = accent.native.withAlphaComponent(0.35)
                out.append(NSAttributedString(string: link.alias ?? (link.target + (link.fragment.map { " › " + $0 } ?? "")), attributes: a))
            }
            cursor = m.range.upperBound
        }
        if cursor < string.endIndex { out.append(NSAttributedString(string: String(string[cursor...]), attributes: attributes(s, paragraph))) }
    }

    private mutating func inline(_ node: Markup, _ s: Inline, _ paragraph: NSParagraphStyle) {
        var s = s
        switch node {
        case let e as Emphasis:
            s.marks.insert(.emphasis)
            inlines(Array(e.inlineChildren), s, style: paragraph)
        case let strong as Strong:
            s.marks.insert(.strong)
            inlines(Array(strong.inlineChildren), s, style: paragraph)
        case let strike as Strikethrough:
            s.marks.insert(.strike)
            inlines(Array(strike.inlineChildren), s, style: paragraph)
        case let c as InlineCode:
            if c.code.first == MathProtection.marker {
                let tex = String(c.code.dropFirst())
                var a = attributes(s, paragraph)
                a[.noteAtom] = NoteAtom("$\(tex)$")
                if let picture = NoteMath.picture(tex, syntax: syntax, display: false, size: s.size * 1.05, color: s.color, dark: dark) {
                    let attachment = NSTextAttachment()
                    attachment.image = picture.image
                    attachment.bounds = CGRect(x: 0, y: -picture.descent, width: picture.size.width, height: picture.size.height)
                    out.append(NSAttributedString(attachment: attachment, attributes: a))
                } else {
                    out.append(mathError(tex, a))
                }
                return
            }
            s.marks.insert(.code)
            out.append(NSAttributedString(string: c.code, attributes: attributes(s, paragraph)))
        case let link as Markdown.Link:
            s.link = link.destination ?? ""
            inlines(Array(link.inlineChildren), s, style: paragraph)
        case let image as Markdown.Image:
            var a = attributes(s, paragraph)
            a[.noteAtom] = NoteAtom("![\(image.plainText)](\(image.source ?? ""))")
            if let picture = NoteImages.load(image.source ?? "", base: baseURL) {
                let size = NoteImages.fit(picture.size, alt: image.plainText, width: width - 2 * NoteLook.boxIndent)
                let attachment = NSTextAttachment()
                attachment.image = picture
                attachment.bounds = CGRect(origin: .zero, size: size)
                out.append(NSAttributedString(attachment: attachment, attributes: a))
            } else {
                a[.foregroundColor] = NoteLook.text3
                out.append(NSAttributedString(string: "🖼 " + (image.plainText.isEmpty ? image.source ?? "" : image.plainText), attributes: a))
            }
        case is SoftBreak, is LineBreak:
            // A line break in the source is one on the page, as in Obsidian.
            out.append(NSAttributedString(string: "\u{2028}", attributes: attributes(s, paragraph)))
        case let html as InlineHTML:
            var a = attributes(s, paragraph)
            a[.noteAtom] = NoteAtom(html.rawHTML)
            a[.foregroundColor] = NoteLook.text3
            out.append(NSAttributedString(string: html.rawHTML, attributes: a))
        default:
            inlines(Array(node.children), s, style: paragraph)
        }
    }

    /// A table cell, drawn outside the note's own text.
    mutating func cell(_ nodes: [Markup], weight: PlatformFont.Weight) -> NSAttributedString {
        let saved = out
        out = NSMutableAttributedString()
        defer { out = saved }
        inlines(nodes, Inline(size: NoteLook.body * 0.9, weight: weight), style: Self.paragraph(Context(), after: 0, lineSpacing: 4))
        return out
    }

    /// A `cb-table` cell, which may hold lists and math as well as text.
    mutating func cell(markdown: String, weight: PlatformFont.Weight) -> NSAttributedString {
        let saved = out
        out = NSMutableAttributedString()
        defer { out = saved }
        for node in ParsedNote(markdown).document.children {
            if let p = node as? Paragraph {
                paragraph(Array(p.inlineChildren), Context(), style: Self.paragraph(Context(), after: 4, lineSpacing: 4))
            } else {
                block(node, Context())
            }
        }
        if out.string.hasSuffix("\n") { out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1)) }
        if weight != .regular { out.addAttribute(.font, value: NoteLook.font(NoteLook.body * 0.9, weight), range: NSRange(location: 0, length: out.length)) }
        return out
    }
}
