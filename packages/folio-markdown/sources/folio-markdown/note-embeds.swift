import Foundation
import Markdown

/// What a note's embeds (`![[노트#제목]]`) and block references (`[[노트#^블록]]`) show. FolioMarkdown reads no files:
/// the app finds the note a link names, and the renderer cuts out the part the link points at.
public struct NoteEmbeds {
    public struct Note {
        /// Tells notes apart, so a note reached again inside itself is not drawn again.
        public var key: String
        public var text: String
        /// The note's math syntax (`latex`, `asciimath`), which may differ from the note it is drawn in.
        public var math: String?

        public init(key: String, text: String, math: String? = nil) {
            self.key = key
            self.text = text
            self.math = math
        }
    }

    /// What an embed that can't be drawn says in its place.
    public struct Labels {
        public var missing: String
        public var loop: String
        public var tooDeep: String

        public init(missing: String, loop: String, tooDeep: String) {
            self.missing = missing
            self.loop = loop
            self.tooDeep = tooDeep
        }
    }

    /// The note being rendered, so embedding itself is caught as a loop at once.
    public var key: String?
    public var labels: Labels
    public var find: (WikiLink) -> Note?
    /// The title of the note an ID names, which a link without its own name shows. Apart from `find`, which only
    /// returns notes it can draw: a link to a LaTeX note still resolves. Nil when no note has the ID.
    public var title: (UUID) -> String?

    public init(key: String?, labels: Labels, title: @escaping (UUID) -> String? = { _ in nil }, find: @escaping (WikiLink) -> Note?) {
        self.key = key
        self.labels = labels
        self.title = title
        self.find = find
    }

    /// A loop is caught by its keys, but notes embedding one another without one could still draw a whole course into
    /// one page; past this depth an embed shows only its link.
    public static let depth = 4
}

extension WikiLink {
    /// A link to a note rather than to an app object or another file: `![[그림.png]]` and `![[slides.pdf]]` embed files,
    /// which this doesn't draw. An extension must start with a letter, so a title like `v1.2` is still a note.
    var namesNote: Bool {
        if let objectKind { return objectKind == "note" }
        let ext = (target as NSString).pathExtension
        return ext.lowercased() == "md" || ext.wholeMatch(of: /[A-Za-z][A-Za-z0-9]{0,4}/) == nil
    }

    /// What an embed or a reference is told apart by in a loop: the note and the part of it.
    func key(in note: String) -> String {
        note + (blockID.map { "#^" + $0 } ?? fragment.map { "#" + $0 } ?? "")
    }
}

extension ParsedNote {
    /// The part of the note a link points at, as markdown: under a heading (the heading included, up to the next
    /// heading as high or higher), a block (its paragraph, list item or callout), or the whole body without either.
    /// Nil when the note has no such heading or block.
    public func section(heading: String?, block: String?) -> String? {
        if let block { return blockSource(block) }
        if let heading { return headingSection(heading) }
        return body
    }

    func headingSection(_ heading: String) -> String? {
        let tops = Array(document.children)
        guard let i = headingIndex(heading, in: tops), let level = (tops[i] as? Heading)?.level,
              let start = lines(of: tops[i])?.lowerBound else { return nil }
        let next = tops[(i + 1)...].first { ($0 as? Heading).map { $0.level <= level } ?? false }
        var end = next.flatMap { lines(of: $0)?.lowerBound }.map { $0 - 1 } ?? bodyLines.count
        while end > start, bodyLines[end - 1].allSatisfy(\.isWhitespace) { end -= 1 }
        return source(start...end)
    }

    /// A list item is the item with its sublists, written as a list of one; anything else is the whole top-level block
    /// (a block ID on a callout's last paragraph names the callout, as the renderer reads it).
    func blockSource(_ id: String) -> String? {
        guard let (range, item) = blockLines(id) else { return nil }
        guard let lines = item else { return source(range) }
        let rows = bodyLines[(lines.lowerBound - 1)...(lines.upperBound - 1)]
        let indent = rows.first?.prefix(while: { $0 == " " || $0 == "\t" }).count ?? 0
        return rows.map { String($0.dropFirst(min(indent, $0.prefix(while: { $0 == " " || $0 == "\t" }).count))) }.joined(separator: "\n")
    }

    /// Headings match as Obsidian matches them: by their text, ignoring case.
    func headingIndex(_ heading: String, in tops: [Markup]) -> Int? {
        let wanted = heading.trimmingCharacters(in: .whitespaces)
        return tops.firstIndex { node in
            guard let h = node as? Heading else { return false }
            let text = h.children.map(HTMLRenderer.sourceText).joined().trimmingCharacters(in: .whitespaces)
            return text.caseInsensitiveCompare(wanted) == .orderedSame || HTMLRenderer.slug(text) == HTMLRenderer.slug(wanted)
        }
    }

    /// The top-level block holding a block ID and, when it is in a list, the deepest item holding it.
    func blockLines(_ id: String) -> (top: ClosedRange<Int>, item: ClosedRange<Int>?)? {
        guard let line = bodyLines.firstIndex(where: { $0.firstMatch(of: BlockID.pattern).map { String($0.1) } == id }).map({ $0 + 1 }),
              let top = document.children.first(where: { lines(of: $0)?.contains(line) ?? false }),
              let range = lines(of: top) else { return nil }
        return (range, deepestItem(in: top, holding: line).flatMap { lines(of: $0) })
    }

    private func deepestItem(in node: Markup, holding line: Int) -> ListItem? {
        guard node is ListItem || node is UnorderedList || node is OrderedList else { return nil }
        for child in node.children where lines(of: child)?.contains(line) ?? false {
            if let deeper = deepestItem(in: child, holding: line) { return deeper }
        }
        return node as? ListItem
    }
}
