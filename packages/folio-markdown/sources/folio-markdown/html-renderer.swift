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

    var counters: [String: Int] = [:]

    // MARK: Blocks

    mutating func blocks(_ nodes: [Markup]) -> String {
        var out = ""
        var previousCallout: String?
        for node in nodes {
            if let quote = node as? BlockQuote, let header = calloutHeader(quote) {
                out += callout(quote, header, attached: header.type == "proof" && CalloutHeader.provable.contains(previousCallout ?? ""))
                previousCallout = header.type
            } else {
                out += block(node)
                previousCallout = nil
            }
        }
        return out
    }

    mutating func block(_ node: Markup) -> String {
        switch node {
        case let p as Paragraph:
            let (html, id) = Self.splitBlockID(inlines(Array(p.inlineChildren)))
            return "<p\(Self.idAttribute(id))>\(html)</p>\n"
        case let h as Heading:
            let html = inlines(Array(h.inlineChildren))
            return "<h\(h.level) id=\"\(Self.escape(Self.slug(h.plainText)))\">\(html)</h\(h.level)>\n"
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
        let box = item.checkbox.map { "<input type=\"checkbox\" disabled\($0 == .checked ? " checked" : "")> " } ?? ""
        // The item's own text renders without <p>, also above a sublist; a <p> there would add a paragraph margin.
        if let p = item.child(at: 0) as? Paragraph {
            let (html, id) = Self.splitBlockID(inlines(Array(p.inlineChildren)))
            return "<li\(Self.idAttribute(id))>\(box)\(html)\(blocks(Array(item.children.dropFirst())))</li>\n"
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
                var r = HTMLRenderer()
                return "<\(tag)\(align)>\(r.inlines(Array((cell as! Markdown.Table.Cell).inlineChildren)))</\(tag)>"
            }.joined()
        }
        let head = "<thead><tr>\(cells(t.head, tag: "th"))</tr></thead>"
        // `rows` is lazy: mapped and joined as is, it interpolates as the sequence's type name, not the rows.
        let body = Array(t.body.rows).map { "<tr>\(cells($0, tag: "td"))</tr>" }.joined()
        return "<table>\(head)<tbody>\(body)</tbody></table>\n"
    }

    // MARK: Callouts

    /// The header comes from the first line only; `plainText` would join the whole paragraph with spaces.
    func calloutHeader(_ quote: BlockQuote) -> CalloutHeader? {
        guard let p = quote.child(at: 0) as? Paragraph else { return nil }
        let firstLine = Array(p.inlineChildren).prefix { !($0 is SoftBreak || $0 is LineBreak) }.map { Self.sourceText($0) }.joined()
        return CalloutHeader(line: firstLine)
    }

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
        return "<details class=\"\(classes)\"\(Self.idAttribute(id))\(open ? " open" : "")>"
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
        return Self.linkWikiLinks(out)
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
    static func linkWikiLinks(_ html: String) -> String {
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

    static func replaceWikiLinks(_ s: String) -> String {
        s.replacing(WikiLink.pattern) { m in
            let link = WikiLink(m)
            let fragment = link.blockID.map { "#^" + $0 } ?? link.fragment.map { "#" + $0 } ?? ""
            let href: String
            if let kind = link.objectKind {
                href = "folio://\(kind)/\(link.target.dropFirst(kind.count + 1))\(fragment)"
            } else {
                href = "folio://note/\(link.target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? link.target)\(fragment)"
            }
            let text = link.alias ?? (link.target + (link.fragment.map { " › " + $0 } ?? ""))
            return link.isEmbed
                ? "<div class=\"embed\" data-href=\"\(href)\"></div>"
                : "<a class=\"wikilink\" href=\"\(href)\">\(text)</a>"
        }
    }

    static func splitBlockID(_ html: String) -> (html: String, id: String?) {
        let (text, id) = BlockID.strip(html)
        return (text, id)
    }

    static func idAttribute(_ id: String?) -> String {
        id.map { " id=\"^\(escape($0))\"" } ?? ""
    }

    static func slug(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: "-")
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
