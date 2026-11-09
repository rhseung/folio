import Foundation
import Markdown

extension WikiLink {
    /// A link to an app object by ID, as link completion writes it: `[[<kind>:<ID>#<fragment>|<alias>]]`. `fragment`
    /// is what goes after `#` (a heading, `^block`, `page=12`). Brackets and `|` would end the link early, so they
    /// don't go into the alias.
    public static func written(_ kind: String, _ id: UUID, fragment: String? = nil, alias: String? = nil, embed: Bool = false) -> String {
        let part = fragment.map { "#" + $0 } ?? ""
        return (embed ? "!" : "") + "[[\(kind):\(id.uuidString)\(part)\(aliasPart(alias))]]"
    }

    /// A link by its `folio://` address, for what has no `<kind>:<ID>` form (a place, a course's page).
    public static func written(address: String, alias: String? = nil) -> String {
        "[[\(address)\(aliasPart(alias))]]"
    }

    static func aliasPart(_ alias: String?) -> String {
        let name = alias.map { a in
            a.split(whereSeparator: { "[]|".contains($0) || $0.isWhitespace }).joined(separator: " ")
        }
        return name.flatMap { $0.isEmpty ? nil : "|" + $0 } ?? ""
    }

    /// Whether an app link pasted at `caret` goes in as a link of its own (`[[material:<ID>#page=2|이름]]`). Not inside
    /// a link being written (`[[…`, `](…`, `<…`), whose target the address is, nor in code or math, where it is text.
    public static func pastesAsLink(in text: NSString, at caret: Int) -> Bool {
        guard SourcePlace.at(caret, in: text) == .text else { return false }
        let line = text.lineRange(for: NSRange(location: caret, length: 0))
        let prefix = text.substring(with: NSRange(location: line.location, length: caret - line.location))
        return prefix.firstMatch(of: #/\[\[[^\]]*$/#) == nil && prefix.firstMatch(of: #/\]\([^)\s]*$/#) == nil && !prefix.hasSuffix("<")
    }

    /// Whether `heading` can follow `#` in a link: `]` and `|` would end it.
    public static func linkable(heading: String) -> Bool {
        !heading.isEmpty && !heading.contains { "[]|#\n".contains($0) }
    }
}

extension ParsedNote {
    public struct HeadingLine: Equatable, Sendable {
        public var level: Int
        public var text: String
    }

    /// A block a link can point at with `#^id`: a paragraph, a list item or a quote (a callout among them).
    public struct LinkableBlock: Equatable, Sendable {
        /// The body line (1-based) its ID is written at the end of.
        public var line: Int
        /// Its first line without markers, to tell it by.
        public var excerpt: String
        public var id: String?
    }

    /// The headings in the order written, their text as written.
    public var headings: [HeadingLine] {
        NoteOutline.headings(in: document).compactMap { h in
            let text = NoteOutline.anchor(of: h)
            return text.isEmpty ? nil : HeadingLine(level: h.level, text: text)
        }
    }

    /// The blocks in the order written. A list item's ID goes after its own text, before its sublist, so that
    /// `blockSource` reads it as the item and not as the last item of the sublist.
    public var linkableBlocks: [LinkableBlock] {
        var out: [LinkableBlock] = []
        func add(_ lines: ClosedRange<Int>?) {
            guard let lines else { return }
            let last = bodyLines[lines.upperBound - 1].trimmingCharacters(in: .whitespaces)
            // A formula or a fence closing there would no longer close with the ID after it.
            guard !last.hasSuffix("$$"), !last.hasSuffix("```"), !last.hasSuffix("~~~") else { return }
            let first = BlockID.strip(String(bodyLines[lines.lowerBound - 1])).text
            let excerpt = first.replacing(#/^[ \t>]*(?:\[![A-Za-z-]+\][+-]?[ \t]*)?(?:(?:[-*+]|\d+[.)])[ \t]+(?:\[[ xX]\][ \t]+)?)?/#, with: "")
                .trimmingCharacters(in: .whitespaces)
            let id = bodyLines[lines.upperBound - 1].firstMatch(of: BlockID.pattern).map { String($0.1) }
            guard !excerpt.isEmpty || id != nil else { return }
            out.append(LinkableBlock(line: lines.upperBound, excerpt: String(excerpt.prefix(80)), id: id))
        }
        func items(_ list: Markup) {
            for case let item as ListItem in list.children {
                if let own = item.children.first(where: { $0 is Paragraph }) { add(lines(of: own)) }
                for case let sub in item.children where sub is UnorderedList || sub is OrderedList { items(sub) }
            }
        }
        for node in document.children {
            switch node {
            case is Paragraph, is BlockQuote: add(lines(of: node))
            case is UnorderedList, is OrderedList: items(node)
            default: break
            }
        }
        return out
    }

    /// Where ` ^id` goes in `text` (UTF-16, as text views count) to name the block whose ID line is `line`: at the end
    /// of that line, before any trailing spaces. Nil when the body can't be lined up with `text`.
    public static func blockTag(in text: String, line: Int, id: String) -> SourceEditing.Edit? {
        let note = ParsedNote(text)
        guard line >= 1, line <= note.bodyLines.count, text.hasSuffix(note.body) else { return nil }
        let before = note.bodyLines[..<(line - 1)].reduce(0) { $0 + $1.utf16.count + 1 }
        let row = note.bodyLines[line - 1]
        let kept = row.utf16.count - row.reversed().prefix { $0 == " " || $0 == "\t" }.count
        let at = text.utf16.count - note.body.utf16.count + before + kept
        return SourceEditing.Edit(range: NSRange(location: at, length: 0), text: " ^" + id, caret: at)
    }
}

extension BlockID {
    /// A new ID none of `taken` has: six letters and digits, as Obsidian makes them, so links stay short.
    public static func make(avoiding taken: Set<String>, using generator: inout some RandomNumberGenerator) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        while true {
            let id = String((0..<6).map { _ in alphabet.randomElement(using: &generator)! })
            if !taken.contains(id) { return id }
        }
    }

    public static func make(avoiding taken: Set<String>) -> String {
        var generator = SystemRandomNumberGenerator()
        return make(avoiding: taken, using: &generator)
    }
}
