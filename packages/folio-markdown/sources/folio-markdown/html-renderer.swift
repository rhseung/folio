import Foundation
import Markdown

/// - Math becomes `<span class="math">` / `<div class="math display">` holding raw TeX for KaTeX to typeset.
/// - Links use the `folio://` scheme: `folio://note/<title>#<heading or ^block>`, `folio://material/<id>#page=12`.
/// - Raw HTML in notes is escaped, not executed; notes come from many sources and the viewer is not a sandbox.
public struct HTMLRenderer {
    public static func render(_ note: ParsedNote) -> String {
        var r = HTMLRenderer()
        return r.blocks(Array(note.document.children))
    }

    public static func render(markdown: String) -> String {
        render(ParsedNote(markdown))
    }

    /// A top-level block of a note and the body lines it was written on.
    public struct Block: Equatable, Sendable {
        public var html: String
        public var lines: ClosedRange<Int>?
    }

    /// The note block by block, so a page can redraw only the blocks that changed and follow an editor by line. Task
    /// boxes carry their item's body line as `data-line`, so a tick can be written back to the source.
    public static func blocks(_ note: ParsedNote, embeds: NoteEmbeds? = nil) -> [Block] {
        var r = HTMLRenderer()
        r.note = note
        r.embeds = embeds
        r.trail = embeds?.key.map { [$0] } ?? []
        return r.rendered(Array(note.document.children)).map { Block(html: $0.html, lines: note.lines(of: $0.node)) }
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

    /// A renderer for part of this note's page (a table cell, an embed) that draws embeds and references as it does.
    func inner() -> HTMLRenderer {
        var r = HTMLRenderer()
        r.embeds = embeds
        r.trail = trail
        r.nested = nested
        r.previewing = previewing
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
            if embeds != nil, let links = Self.embedsOnly(p) { return links.map { embed($0) }.joined() }
            let (html, id) = Self.splitBlockID(inlines(Array(p.inlineChildren)))
            return "<p\(idAttribute(id))>\(html)</p>\n"
        case let h as Heading:
            let html = inlines(Array(h.inlineChildren))
            let id = nested ? "" : " id=\"\(Self.escape(Self.slug(h.plainText)))\""
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
        case CBTable.language:
            return CBTable.render(json: code)
        case CBWidget.language:
            return CBWidget.render(json: code)
        case let language?:
            return "<pre data-lang=\"\(Self.escape(language))\"><code class=\"language-\(Self.escape(language))\">\(Self.escape(code))</code></pre>\n"
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
                return "<\(tag)\(align)>\(r.inlines(Array((cell as! Markdown.Table.Cell).inlineChildren)))</\(tag)>"
            }.joined()
        }
        let head = "<thead><tr>\(cells(t.head, tag: "th"))</tr></thead>"
        // `rows` is lazy: mapped and joined as is, it interpolates as the sequence's type name, not the rows.
        let body = Array(t.body.rows).map { "<tr>\(cells($0, tag: "td"))</tr>" }.joined()
        return "<table>\(head)<tbody>\(body)</tbody></table>\n"
    }

    // MARK: Callouts

    func calloutHeader(_ quote: BlockQuote) -> CalloutHeader? { quote.calloutHeader }

    /// Inline markdown text close to the source, with protected math turned back into `$...$`.
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
        return linkWikiLinks(out)
    }

    mutating func inline(_ node: Markup) -> String {
        switch node {
        case let t as Markdown.Text:
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

    /// Turns `[[...]]` in rendered inline HTML into links, outside `<code>` and math spans.
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

    func replaceWikiLinks(_ s: String) -> String {
        s.replacing(WikiLink.pattern) { m in
            let link = WikiLink(m)
            let href = link.href
            // The link was read from rendered HTML, so its target and alias are escaped already; a found title is not.
            let found = noteTitle(link)
            let text = link.alias ?? ((found.title.map(Self.escape) ?? link.target) + (link.fragment.map { " › " + $0 } ?? ""))
            return link.isEmbed
                // A link, not a block: it stands inside the paragraph the embed was written in, with other text.
                ? "<a class=\"embed\" href=\"\(href)\">\(text)</a>"
                : "<a class=\"wikilink\(found.missing ? " missing" : "")\" href=\"\(href)\">\(text)</a>" + preview(link)
        }
    }

    /// For a link by ID, the title of the note it names, which a link without its own name shows. `missing` when no
    /// note has the ID, which only a page drawing embeds can tell; elsewhere (the Claude panel, PDF export) the link
    /// shows its target.
    func noteTitle(_ link: WikiLink) -> (title: String?, missing: Bool) {
        guard let id = link.noteID, let embeds else { return (nil, false) }
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
              text.replacing(WikiLink.pattern, with: "").allSatisfy(\.isWhitespace) else { return nil }
        return links
    }

    /// The part of another note an embed points at, drawn under its name, which opens the note. One that can't be
    /// drawn (missing, inside itself, too deep) says why in its place.
    func embed(_ link: WikiLink) -> String {
        let part = link.blockID.map { " › ^" + $0 } ?? link.fragment.map { " › " + $0 } ?? ""
        let name = Self.escape(link.alias ?? ((noteTitle(link).title ?? link.target) + part))
        let head = "<a class=\"embed-title\" href=\"\(Self.escape(link.href))\">\(name)</a>"
        let empty = { (why: String) in "<div class=\"embed embed-empty\">\(head)<p class=\"embed-note\">\(Self.escape(why))</p></div>\n" }
        guard let embeds else { return "<p>\(head)</p>\n" }
        guard trail.count <= NoteEmbeds.depth else { return empty(embeds.labels.tooDeep) }
        guard let found = embeds.find(link), let section = ParsedNote(found.text).section(heading: link.fragment, block: link.blockID) else {
            return empty(embeds.labels.missing)
        }
        let key = link.key(in: found.key)
        guard !trail.contains(key) else { return empty(embeds.labels.loop) }
        var child = inner()
        child.trail = trail + [key]
        child.nested = true
        let body = child.blocks(Array(ParsedNote(section).document.children))
        return "<div class=\"embed\"\(Self.mathAttribute(found.math))>\(head)<div class=\"embed-body\">\n\(body)</div></div>\n"
    }

    /// A block reference carries the block it names, which the page shows while the pointer rests on the link. A
    /// template holds it: its content is inert and may stand inside the paragraph, where a block element can't.
    func preview(_ link: WikiLink) -> String {
        guard let embeds, !previewing, let block = link.blockID, link.namesNote else { return "" }
        // The link was read from rendered HTML, so its target is escaped there.
        var named = link
        named.target = Self.unescape(link.target)
        guard trail.count <= NoteEmbeds.depth, let found = embeds.find(named),
              let section = ParsedNote(found.text).section(heading: nil, block: block) else {
            return "<template class=\"ref-preview\"><p class=\"embed-note\">\(Self.escape(embeds.labels.missing))</p></template>"
        }
        var child = inner()
        child.trail = trail + [named.key(in: found.key)]
        child.nested = true
        child.previewing = true
        let body = child.blocks(Array(ParsedNote(section).document.children))
        return "<template class=\"ref-preview\"\(Self.mathAttribute(found.math))>\(body)</template>"
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

    /// A heading's `id`, which a link to the heading scrolls to.
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
        let firstLine = Array(p.inlineChildren).prefix { !($0 is SoftBreak || $0 is LineBreak) }.map { HTMLRenderer.sourceText($0) }.joined()
        return CalloutHeader(line: firstLine)
    }
}
