import Foundation
import Markdown

/// - Math becomes `<span class="math">` / `<div class="math display">` holding raw TeX for KaTeX to typeset.
/// - Links use the `folio://` scheme: `folio://note/<title>#<heading or ^block>`, `folio://material/<id>#page=12`.
/// - Raw HTML in notes is escaped, not executed; notes come from many sources and the viewer is not a sandbox.
public struct HTMLRenderer {
    public static func render(_ note: ParsedNote) -> String {
        blocks(note, embeds: nil, lines: false).map(\.html).joined()
    }

    public static func render(markdown: String) -> String {
        render(ParsedNote(markdown))
    }

    /// An answer in the Claude panel: as a note, but `tex` and `latex` fences stay code.
    public static func render(answer: String) -> String {
        blocks(ParsedNote(answer), embeds: nil, lines: false, mathFences: false).map(\.html).joined()
    }

    public struct Block: Equatable, Sendable {
        public var html: String
        public var lines: ClosedRange<Int>?
    }

    /// The note block by block, so a page can redraw only the blocks that changed and follow an editor by line. Task
    /// boxes carry their item's body line as `data-line`, so a tick can be written back to the source.
    public static func blocks(_ note: ParsedNote, embeds: NoteEmbeds? = nil) -> [Block] {
        blocks(note, embeds: embeds, lines: true)
    }

    static func blocks(_ note: ParsedNote, embeds: NoteEmbeds?, lines: Bool, mathFences: Bool = true) -> [Block] {
        var r = HTMLRenderer()
        r.mathFences = mathFences
        if lines { r.note = note }
        r.embeds = embeds
        r.trail = embeds?.key.map { [$0] } ?? []
        let book = FootnoteBook(note.document)
        r.footnotes = book

        var out = r.rendered(Array(note.document.children)).map { Block(html: $0.html, lines: note.lines(of: $0.node)) }
        let section = r.footnoteSection()
        guard !section.isEmpty else { return out }
        // The list follows the editor from its last definition, unless a block below that is drawn above the list.
        let definitions = note.document.children.compactMap {
            ($0 as? Paragraph).flatMap { book.isDefinition($0) ? note.lines(of: $0) : nil }
        }
        let last = out.filter { !$0.html.isEmpty }.compactMap(\.lines?.lowerBound).max() ?? 0
        out.append(Block(html: section, lines: definitions.last.flatMap { $0.lowerBound >= last ? $0 : nil }))
        return out
    }

    var counters: [String: Int] = [:]
    var note: ParsedNote?
    /// Without it embeds and block references show only their links, as in the Claude panel and PDF export.
    var embeds: NoteEmbeds?
    /// The notes (and parts of them) this one is drawn inside, outermost first.
    var trail: [String] = []
    /// Inside an embed or a reference's preview, where an `id` would repeat the other note's: a link to a heading
    /// or block scrolls to the first element with its id.
    var nested = false
    /// Inside a reference's preview, whose own references get no preview: it would hold the next one, and so on.
    var previewing = false
    /// The note's footnotes, numbered as references to them are drawn.
    var footnotes: FootnoteBook?
    /// Inside a markdown link's text, where an address can't be a link of its own: anchors don't nest.
    var inLink = false
    /// Off in the Claude panel, whose `tex` and `latex` fences hold source to copy, not a formula to read; `math` is
    /// a formula there too, as it was before fences chose a syntax.
    var mathFences = true

    func mathFence(_ language: String) -> MathFence.Syntax? {
        guard let syntax = MathFence.syntax(language) else { return nil }
        return mathFences || language.split(whereSeparator: \.isWhitespace).first == "math" ? syntax : nil
    }

    func inner() -> HTMLRenderer {
        var r = HTMLRenderer()
        r.embeds = embeds
        r.trail = trail
        r.nested = nested
        r.previewing = previewing
        r.footnotes = footnotes
        r.mathFences = mathFences
        return r
    }

    // MARK: Blocks

    mutating func blocks(_ nodes: [Markup]) -> String {
        rendered(nodes).map(\.html).joined()
    }

    mutating func rendered(_ nodes: [Markup]) -> [(node: Markup, html: String)] {
        var out: [(node: Markup, html: String)] = []
        var previousCallout: String?
        for node in nodes {
            let html: String
            if let quote = node as? BlockQuote, let header = calloutHeader(quote) {
                html = callout(quote, header, attached: header.type == "proof" && CalloutHeader.provable.contains(previousCallout ?? ""))
                previousCallout = header.type
            } else {
                html = block(node)
                previousCallout = nil
            }
            out.append((node, html))
        }
        return out
    }

    mutating func block(_ node: Markup) -> String {
        switch node {
        case let p as Paragraph:
            // A definition is drawn in the list at the note's end, not where it was written.
            if footnotes?.isDefinition(p) == true { return "" }
            if NoteOutline.isContents(p) { return contents(of: p.root) }
            if embeds != nil, let links = Self.embedsOnly(p) { return links.map { embed($0) }.joined() }
            let (html, id) = Self.splitBlockID(inlines(Array(p.inlineChildren)))
            return "<p\(idAttribute(id))>\(html)</p>\n"
        case let h as Heading:
            let html = inlines(Array(h.inlineChildren))
            let id = nested ? "" : " id=\"\(Self.escape(NoteOutline.id(of: h)))\""
            return "<h\(h.level)\(id)>\(html)</h\(h.level)>\n"
        case let q as BlockQuote:
            return "<blockquote>\n\(blocks(Array(q.children)))</blockquote>\n"
        case let c as CodeBlock:
            return codeBlock(c)
        case let l as UnorderedList:
            return "<ul>\n\(listItems(Array(l.listItems)))</ul>\n"
        case let l as OrderedList:
            let start = l.startIndex == 1 ? "" : " start=\"\(l.startIndex)\""
            return "<ol\(start)>\n\(listItems(Array(l.listItems)))</ol>\n"
        case let t as Markdown.Table:
            return table(t)
        case is ThematicBreak:
            return "<hr>\n"
        case let h as HTMLBlock:
            return "<pre class=\"raw-html\">\(Self.escape(h.rawHTML))</pre>\n"
        default:
            return blocks(Array(node.children))
        }
    }

    /// `[TOC]`: the headings of the document it is written in, nested by level, each a link to its heading. Drawn
    /// from another note (an embed), where its headings have no ids, the items are no links.
    func contents(of document: Markup) -> String {
        let headings = NoteOutline.headings(in: document).filter { $0.level <= NoteOutline.depth }
        guard !headings.isEmpty else { return "" }
        let levels = Set(headings.map(\.level)).sorted()
        let items = headings.map { h in
            var r = HTMLRenderer()
            r.inLink = true
            // The heading's own links and references would nest inside the item's link.
            let title = Self.splitBlockID(r.inlines(Array(h.inlineChildren))).html
                .replacing(/<template\b(?s:.*?)<\/template>/, with: "").replacing(/<\/?a\b[^>]*>/, with: "")
                .replacing(Footnotes.reference, with: "")
            let item = nested ? "<span>\(title)</span>" : "<a href=\"#\(Self.escape(NoteOutline.id(of: h)))\">\(title)</a>"
            return (levels.firstIndex(of: h.level) ?? 0, item)
        }

        // Each item holds the deeper ones after it, up to the next one no deeper.
        func list(_ items: ArraySlice<(Int, String)>) -> String {
            guard !items.isEmpty else { return "" }
            var out = "<ul>"
            var i = items.startIndex
            while i < items.endIndex {
                let depth = items[i].0
                let end = items[(i + 1)...].firstIndex { $0.0 <= depth } ?? items.endIndex
                out += "<li>\(items[i].1)\(list(items[(i + 1)..<end]))</li>"
                i = end
            }
            return out + "</ul>"
        }
        return "<nav class=\"toc\">\(list(items[...]))</nav>\n"
    }

    mutating func listItems(_ items: [ListItem]) -> String {
        var out = ""
        for item in items { out += listItem(item) }
        return out
    }

    mutating func listItem(_ item: ListItem) -> String {
        let line = note?.lines(of: item).map { " data-line=\"\($0.lowerBound)\"" } ?? ""
        let box = item.checkbox.map { "<input type=\"checkbox\"\(line) disabled\($0 == .checked ? " checked" : "")> " } ?? ""
        // The item's own text renders without <p>, also above a sublist; a <p> there would add a paragraph margin.
        if let p = item.child(at: 0) as? Paragraph {
            let (html, id) = Self.splitBlockID(inlines(Array(p.inlineChildren)))
            return "<li\(idAttribute(id))>\(box)\(html)\(blocks(Array(item.children.dropFirst())))</li>\n"
        }
        return "<li>\(box)\(blocks(Array(item.children)))</li>\n"
    }

    mutating func codeBlock(_ c: CodeBlock) -> String {
        let code = c.code.hasSuffix("\n") ? String(c.code.dropLast()) : c.code
        switch c.language {
        case MathProtection.blockLanguage:
            return "<div class=\"math display\">\(Self.escape(code))</div>\n"
        case let language? where mathFence(language) != nil:
            // Its own `data-math`, which the page reads before the note's (web/src/reader.js).
            return "<div class=\"math display\"\(Self.mathAttribute(mathFence(language)?.rawValue))>\(Self.escape(code))</div>\n"
        case CBTable.language:
            let r = inner()
            return CBTable.render(json: code) { text in
                var cell = r
                return cell.blocks(Array(ParsedNote(text).document.children))
            }
        case CBWidget.language:
            return CBWidget.render(json: code)
        case let language?:
            return
                "<pre data-lang=\"\(Self.escape(language))\"><code class=\"language-\(Self.escape(language))\">\(Self.escape(code))</code></pre>\n"
        case nil:
            return "<pre><code>\(Self.escape(code))</code></pre>\n"
        }
    }

    mutating func table(_ t: Markdown.Table) -> String {
        let aligns = t.columnAlignments
        func cells(_ row: some Markup, tag: String) -> String {
            row.children.enumerated().map { i, cell in
                let align = i < aligns.count ? aligns[i].map { " style=\"text-align:\($0)\"" } ?? "" : ""
                var r = inner()
                let html = r.inlines(Array((cell as! Markdown.Table.Cell).inlineChildren))
                let word = Self.isShortWord(Self.unescape(html.replacing(/<[^>]*>/, with: ""))) ? " class=\"word\"" : ""
                return "<\(tag)\(word)\(align)>\(html)</\(tag)>"
            }.joined()
        }
        let head = "<thead><tr>\(cells(t.head, tag: "th"))</tr></thead>"
        // `rows` is lazy: mapped and joined as is, it interpolates as the sequence's type name, not the rows.
        let body = Array(t.body.rows).map { "<tr>\(cells($0, tag: "td"))</tr>" }.joined()
        return "<table>\(head)<tbody>\(body)</tbody></table>\n"
    }

    /// A cell showing one short word (`10/26(월)`, `9주차-1`) is drawn on one line. WebKit breaks such a word after `/` and
    /// `(` even with `keep-all` and `overflow-wrap: normal`, so beside a long column a date stood as `10/` `26(` `월)`.
    /// A longer word may still wrap, so one long name or address doesn't push the table past the column.
    static func isShortWord(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && t.count <= 16 && !t.contains(where: \.isWhitespace)
    }

    // MARK: Callouts

    func calloutHeader(_ quote: BlockQuote) -> CalloutHeader? { quote.calloutHeader }

    static func sourceText(_ node: Markup) -> String {
        switch node {
        case let t as Markdown.Text: t.string
        case let c as InlineCode: c.code.first == MathProtection.marker ? "$\(c.code.dropFirst())$" : "`\(c.code)`"
        case let e as Emphasis: "*" + e.children.map(sourceText).joined() + "*"
        case let s as Strong: "**" + s.children.map(sourceText).joined() + "**"
        default: node.children.map(sourceText).joined()
        }
    }

    mutating func callout(_ quote: BlockQuote, _ header: CalloutHeader, attached: Bool) -> String {
        var label = header.type.prefix(1).uppercased() + header.type.dropFirst()
        var title = header.title
        if CalloutHeader.numbered.contains(header.type) {
            if let explicit = header.explicitNumber {
                // `Theorem 1.20 (Name)` keeps the textbook number; drop it from the title so it isn't shown twice.
                label += " " + explicit
                title = title.replacingOccurrences(of: #"^(?:[A-Za-z]+\s+)?\#(explicit)\s*"#, with: "", options: .regularExpression)
            } else {
                counters[header.type, default: 0] += 1
                label += " \(counters[header.type]!)"
            }
        }

        let first = quote.child(at: 0) as! Paragraph
        let rest = Array(first.inlineChildren.drop { !($0 is SoftBreak || $0 is LineBreak) }.dropFirst())
        var body = ""
        var id: String?
        if !rest.isEmpty {
            (body, id) = Self.splitBlockID(inlines(rest))
            body = "<p>\(body)</p>\n"
        }
        var inner = blocks(Array(quote.children.dropFirst()))
        // A block ID on the callout's last paragraph names the whole callout, as in Obsidian.
        if let m = inner.firstMatch(of: /<p id="\^([A-Za-z0-9-]+)">((?s:.*))<\/p>\n$/), !m.2.contains("<p") {
            id = String(m.1)
            inner.replaceSubrange(m.range, with: "<p>\(m.2)</p>\n")
        }
        body += inner

        // A proof right under a theorem (or lemma, corollary, proposition) belongs to it and starts folded.
        let open = attached ? false : !header.folded
        let classes = "callout callout-\(header.type)" + (attached ? " attached" : "")
        let titleHTML = title.isEmpty ? "" : " <span class=\"callout-title\">\(inlineMarkdown(title))</span>"
        return "<details class=\"\(classes)\"\(idAttribute(id))\(open ? " open" : "")>"
            + "<summary><span class=\"callout-label\">\(Self.escape(label))</span>\(titleHTML)</summary>\n\(body)</details>\n"
    }

    mutating func inlineMarkdown(_ text: String) -> String {
        guard let p = Document(parsing: MathProtection.protectInline(text)).child(at: 0) as? Paragraph else { return Self.escape(text) }
        return inlines(Array(p.inlineChildren))
    }

    // MARK: Inlines

    mutating func inlines(_ nodes: [Markup]) -> String {
        var out = ""
        for node in nodes { out += inline(node) }
        return linkFootnotes(linkAddresses(linkWikiLinks(out)))
    }

    mutating func inline(_ node: Markup) -> String {
        switch node {
        case let t as Markdown.Text:
            // Only a footnote definition's first text starts with the marker. Its label is the list's; where the
            // definition isn't drawn as one, it shows as written.
            if t.string.first == Footnotes.marker {
                guard footnotes != nil, let m = t.string.prefixMatch(of: Footnotes.maskedStart) else {
                    return Self.escape("[" + t.string.dropFirst())
                }
                return Self.escape(String(t.string[m.range.upperBound...]))
            }
            return Self.escape(t.string)
        case let e as Emphasis:
            return "<em>\(inlines(Array(e.inlineChildren)))</em>"
        case let s as Strong:
            return "<strong>\(inlines(Array(s.inlineChildren)))</strong>"
        case let s as Strikethrough:
            return "<del>\(inlines(Array(s.inlineChildren)))</del>"
        case let c as InlineCode:
            if c.code.first == MathProtection.marker {
                return "<span class=\"math\">\(Self.escape(String(c.code.dropFirst())))</span>"
            }
            return "<code>\(Self.escape(c.code))</code>"
        case let l as Markdown.Link:
            let outer = inLink
            inLink = true
            defer { inLink = outer }
            return "<a href=\"\(Self.escape(l.destination ?? ""))\">\(inlines(Array(l.inlineChildren)))</a>"
        case let i as Markdown.Image:
            // Obsidian's `![alt|300](src)`: a width after the last bar; without it the image takes the column.
            var alt = i.plainText, width = ""
            if let m = alt.firstMatch(of: /\s*\|\s*(\d+)(?:x\d+)?$/) {
                width = " width=\"\(m.1)\""
                alt = String(alt[..<m.range.lowerBound])
            }
            return "<img src=\"\(Self.escape(i.source ?? ""))\" alt=\"\(Self.escape(alt))\"\(width)>"
        // A line break in the source is one on the page, as in Obsidian and in the editor, which shows notes line by line.
        case is SoftBreak:
            return "<br>\n"
        case is LineBreak:
            return "<br>\n"
        case let h as InlineHTML:
            return Self.escape(h.rawHTML)
        default:
            return inlines(Array(node.children))
        }
    }

    // MARK: Helpers

    func linkWikiLinks(_ html: String) -> String {
        guard html.contains("[[") else { return html }
        let protected = /(<code>.*?<\/code>|<span class="math">.*?<\/span>)/
        var out = ""
        var cursor = html.startIndex
        for m in html.matches(of: protected) {
            out += replaceWikiLinks(String(html[cursor..<m.range.lowerBound])) + html[m.range]
            cursor = m.range.upperBound
        }
        return out + replaceWikiLinks(String(html[cursor...]))
    }

    /// A label nothing defines stays as written, as in GFM.
    func linkFootnotes(_ html: String) -> String {
        guard let footnotes, html.contains("[^") else { return html }
        let protected = /(<code>.*?<\/code>|<span class="math">.*?<\/span>)/
        let nested = nested
        let replace = { (s: Substring) -> String in
            String(
                s.replacing(Footnotes.reference) { m in
                    guard let (n, use) = footnotes.use(Self.unescape(String(m.1))) else { return String(m.0) }
                    // Inside an embed or a preview, ids would repeat the page's own.
                    if nested { return "<sup class=\"footnote-ref\">\(n)</sup>" }
                    return "<sup class=\"footnote-ref\"><a href=\"#fn-\(n)\" id=\"\(Self.footnoteRef(n, use))\">\(n)</a></sup>"
                })
        }
        var out = ""
        var cursor = html.startIndex
        for m in html.matches(of: protected) {
            out += replace(html[cursor..<m.range.lowerBound]) + html[m.range]
            cursor = m.range.upperBound
        }
        return out + replace(html[cursor...])
    }

    static func footnoteRef(_ n: Int, _ use: Int) -> String { use == 1 ? "fnref-\(n)" : "fnref-\(n)-\(use)" }

    /// Drawing one footnote can number another, which then comes after it, so the list is read while it grows.
    mutating func footnoteSection() -> String {
        guard let footnotes else { return "" }
        var items = ""
        var i = 0
        while i < footnotes.numbered.count {
            let key = footnotes.numbered[i]
            let n = i + 1
            i += 1
            guard let definition = footnotes.definitions[key] else { continue }
            let body = Self.splitBlockID(inlines(definition)).html
            if nested {
                items += "<li><p>\(body)</p></li>\n"
                continue
            }
            let back = (1...max(1, footnotes.uses(of: key))).map { use in
                "<a class=\"footnote-back\" href=\"#\(Self.footnoteRef(n, use))\">↩\u{FE0E}\(use == 1 ? "" : "<sup>\(use)</sup>")</a>"
            }.joined(separator: " ")
            items += "<li id=\"fn-\(n)\"><p>\(body) \(back)</p></li>\n"
        }
        return items.isEmpty ? "" : "<section class=\"footnotes\"><ol>\n\(items)</ol></section>\n"
    }

    func replaceWikiLinks(_ s: String) -> String {
        s.replacing(WikiLink.pattern) { m in
            let link = WikiLink(m)
            // The link was read from rendered HTML, so its target and alias are escaped already; a found title is not,
            // nor an address's heading, which was unescaped from `%..`.
            let href = link.isAddress ? Self.escape(Self.unescape(link.href)) : link.href
            var named = link
            named.target = Self.unescape(link.target)
            let found = noteTitle(named)
            let fragment = link.fragment.map { " › " + (link.isAddress ? Self.escape(Self.unescape($0)) : $0) } ?? ""
            let text = link.alias ?? objectName(named).map(Self.escape) ?? ((found.title.map(Self.escape) ?? link.target) + fragment)
            let missing = found.missing ? " missing" : ""
            return link.isEmbed
                // A link, not a block: it stands inside the paragraph the embed was written in, with other text.
                ? "<a class=\"embed\(missing)\" href=\"\(href)\">\(text)</a>"
                : "<a class=\"wikilink\(missing)\" href=\"\(href)\">\(text)</a>" + preview(link)
        }
    }

    func objectName(_ link: WikiLink) -> String? {
        guard let embeds, link.isAppLink, !link.namesNote else { return nil }
        return embeds.name(link.href)
    }

    /// A `folio://` address written as it is, which markdown makes no link of, as GFM links a bare `https://`. Not
    /// inside another link, a tag, code or math. Punctuation closing a sentence isn't part of it, except in a heading
    /// anchor (`trimmedAddress`).
    func linkAddresses(_ html: String) -> String {
        guard !inLink, html.localizedCaseInsensitiveContains("folio://") else { return html }
        let protected = /(?s)(<a\b[^>]*>.*?<\/a>|<code>.*?<\/code>|<span class="math">.*?<\/span>|<template\b.*?<\/template>|<[^>]*>)/
        let address = /[Ff][Oo][Ll][Ii][Oo]:\/\/[^\s<>"'`(){}\[\]\\|&]+/
        let replace = { (s: Substring) -> String in
            String(
                s.replacing(address) { m in
                    let written = String(m.0)
                    let kept = Self.trimmedAddress(written)
                    return "<a href=\"\(kept)\">\(kept)</a>" + written.dropFirst(kept.count)
                })
        }
        var out = ""
        var cursor = html.startIndex
        for m in html.matches(of: protected) {
            out += replace(html[cursor..<m.range.lowerBound]) + html[m.range]
            cursor = m.range.upperBound
        }
        return out + replace(html[cursor...])
    }

    /// FolioDomain's `AppLink.trimmed`, which the editors find addresses by, so both views link the same text: kept
    /// on a page, time or block anchor, the full stop would make it read as a heading and open at the top.
    static func trimmedAddress(_ written: String) -> String {
        if let hash = written.firstIndex(of: "#") {
            let anchor = written[written.index(after: hash)...]
            guard anchor.hasPrefix("page=") || anchor.hasPrefix("t=") || anchor.hasPrefix("^") else { return written }
        }
        return String(written.reversed().drop { ".,;:!?".contains($0) }.reversed())
    }

    /// For a link by ID, the title of the note it names, which a link without its own name shows. `missing` when no
    /// note has the ID, or none the title a link by title names, which only a page drawing embeds can tell; elsewhere
    /// (the Claude panel, PDF export) the link shows its target. A link to a file or another app object is left alone.
    func noteTitle(_ link: WikiLink) -> (title: String?, missing: Bool) {
        guard let embeds, link.namesNote else { return (nil, false) }
        guard let id = link.noteID else { return (nil, !embeds.hasNote(link.target)) }
        let title = embeds.title(id)
        return (title, title == nil)
    }

    // MARK: Embeds and references

    /// The links of a paragraph holding nothing but note embeds, each of which is drawn as a block in its place. An
    /// embed beside other text stays a link: a block can't stand inside a paragraph.
    static func embedsOnly(_ p: Paragraph) -> [WikiLink]? {
        var text = ""
        for child in p.inlineChildren {
            switch child {
            case let t as Markdown.Text: text += t.string
            case is SoftBreak, is LineBreak: text += "\n"
            default: return nil
            }
        }
        let links = WikiLink.all(in: text)
        guard !links.isEmpty, links.allSatisfy({ $0.isEmbed && $0.namesNote }),
            text.replacing(WikiLink.pattern, with: "").allSatisfy(\.isWhitespace)
        else { return nil }
        return links
    }

    /// The part of another note an embed points at, drawn under its name, which opens the note. One that can't be
    /// drawn (missing, inside itself, too deep) says why in its place.
    func embed(_ link: WikiLink) -> String {
        let part = link.blockID.map { " › ^" + $0 } ?? link.fragment.map { " › " + $0 } ?? ""
        let found = noteTitle(link)
        let name = Self.escape(link.alias ?? ((found.title ?? link.target) + part))
        let head = "<a class=\"embed-title\(found.missing ? " missing" : "")\" href=\"\(Self.escape(link.href))\">\(name)</a>"
        let empty = { (why: String) in "<div class=\"embed embed-empty\">\(head)<p class=\"embed-note\">\(Self.escape(why))</p></div>\n" }

        guard let embeds else { return "<p>\(head)</p>\n" }
        guard trail.count <= NoteEmbeds.depth else { return empty(embeds.labels.tooDeep) }
        guard let found = embeds.find(link), let section = ParsedNote(found.text).section(heading: link.fragment, block: link.blockID)
        else {
            return empty(embeds.labels.missing)
        }
        let key = link.key(in: found.key)
        guard !trail.contains(key) else { return empty(embeds.labels.loop) }

        var child = inner()
        child.trail = trail + [key]
        child.nested = true
        // The part shown may reference footnotes defined elsewhere in its note, usually at the end.
        child.footnotes = FootnoteBook(ParsedNote(found.text).document)
        let body = child.blocks(Array(ParsedNote(section).document.children)) + child.footnoteSection()
        return "<div class=\"embed\"\(Self.mathAttribute(found.math))>\(head)<div class=\"embed-body\">\n\(body)</div></div>\n"
    }

    /// A block reference carries the block it names, which the page shows while the pointer rests on the link. A
    /// template holds it: its content is inert and may stand inside the paragraph, where a block element can't.
    func preview(_ link: WikiLink) -> String {
        guard !previewing else { return "" }
        // The link was read from rendered HTML, so its target is escaped there.
        var named = link
        named.target = Self.unescape(link.target)
        guard let card = card(named) else { return "" }
        return "<template class=\"ref-preview\"\(Self.mathAttribute(card.math))>\(card.html)</template>"
    }

    public struct ReferenceCard: Equatable, Sendable {
        public var html: String
        public var math: String?
    }

    /// The card a block reference (`[[노트#^블록]]`, as written in the source) shows in the preview, for a view that
    /// shows the source and floats the card itself. Nil for any other link.
    public static func referenceCard(_ link: WikiLink, embeds: NoteEmbeds) -> ReferenceCard? {
        var r = HTMLRenderer()
        r.embeds = embeds
        r.trail = embeds.key.map { [$0] } ?? []
        return r.card(link)
    }

    /// Its own references get no card.
    func card(_ link: WikiLink) -> ReferenceCard? {
        guard let embeds, let block = link.blockID, link.namesNote else { return nil }
        guard trail.count <= NoteEmbeds.depth, let found = embeds.find(link),
            let section = ParsedNote(found.text).section(heading: nil, block: block)
        else {
            return ReferenceCard(html: "<p class=\"embed-note\">\(Self.escape(embeds.labels.missing))</p>", math: nil)
        }

        var child = inner()
        child.trail = trail + [link.key(in: found.key)]
        child.nested = true
        child.previewing = true
        child.footnotes = FootnoteBook(ParsedNote(found.text).document)
        let body = child.blocks(Array(ParsedNote(section).document.children)) + child.footnoteSection()
        return ReferenceCard(html: body, math: found.math)
    }

    static func mathAttribute(_ math: String?) -> String {
        math.map { " data-math=\"\(escape($0))\"" } ?? ""
    }

    static func splitBlockID(_ html: String) -> (html: String, id: String?) {
        let (text, id) = BlockID.strip(html)
        return (text, id)
    }

    func idAttribute(_ id: String?) -> String {
        nested ? "" : id.map { " id=\"^\(Self.escape($0))\"" } ?? ""
    }

    public static func slug(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: "-")
    }

    static func unescape(_ s: String) -> String {
        s.replacing("&quot;", with: "\"").replacing("&lt;", with: "<").replacing("&gt;", with: ">").replacing("&amp;", with: "&")
    }

    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(c)
            }
        }
        return out
    }
}

extension BlockQuote {
    /// The header comes from the first line only; `plainText` would join the whole paragraph with spaces.
    public var calloutHeader: CalloutHeader? {
        guard let p = child(at: 0) as? Paragraph else { return nil }
        let firstLine = Array(p.inlineChildren).prefix { !($0 is SoftBreak || $0 is LineBreak) }.map { HTMLRenderer.sourceText($0) }
            .joined()
        return CalloutHeader(line: firstLine)
    }
}
