import Foundation
import Markdown

public struct NoteOutline: Equatable, Sendable {
    public struct Entry: Equatable, Hashable, Sendable {
        public var level: Int
        public var title: String
        public var anchor: String
        public var id: String
        public var line: Int
        public var location: Int
    }

    public var entries: [Entry]

    public static let depth = 3

    public init(entries: [Entry]) { self.entries = entries }

    public init(_ text: String) { self.init(ParsedNote(text), text: text) }

    public init(_ note: ParsedNote, text: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let offset = max(0, lines.count - note.bodyLines.count)
        var starts = [0]
        starts.reserveCapacity(lines.count)
        for row in lines.dropLast() { starts.append(starts[starts.count - 1] + row.utf16.count + 1) }

        entries = Self.headings(in: note.document).compactMap { h in
            guard let body = note.lines(of: h), body.lowerBound + offset <= lines.count else { return nil }
            let line = body.lowerBound + offset
            let anchor = Self.anchor(of: h)
            guard !anchor.isEmpty else { return nil }
            return Entry(
                level: h.level, title: Self.title(of: h), anchor: anchor, id: Self.id(of: h), line: line, location: starts[line - 1])
        }
    }

    // MARK: Which headings

    public static func headings(in document: Markup) -> [Heading] {
        document.children.compactMap { $0 as? Heading }
    }

    public static func anchor(of heading: Heading) -> String {
        heading.children.map(HTMLRenderer.sourceText).joined().trimmingCharacters(in: .whitespaces)
    }

    public static func id(of heading: Heading) -> String {
        HTMLRenderer.slug(heading.plainText)
    }

    public static func title(of heading: Heading) -> String {
        func text(_ node: Markup) -> String {
            switch node {
            case let t as Markdown.Text: t.string
            case let c as InlineCode: c.code.first == MathProtection.marker ? String(c.code.dropFirst()) : c.code
            case is Markdown.Image: ""
            case is SoftBreak, is LineBreak: " "
            default: node.children.map(text).joined()
            }
        }
        let written = BlockID.strip(heading.children.map(text).joined()).text
        let linked = written.replacing(WikiLink.pattern) { m in
            let link = WikiLink(m)
            return link.alias ?? link.target
        }
        return linked.replacing(Footnotes.reference, with: "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: Reading along

    public func current(at line: Int) -> Int? {
        entries.lastIndex { $0.line <= line }
    }

    public func owner(of i: Int) -> Int? {
        guard entries[i].level > Self.depth else { return nil }
        return entries[..<i].lastIndex { $0.level <= Self.depth }
    }

    public func folds(_ i: Int) -> Bool {
        entries.indices.dropFirst(i + 1).first.map { owner(of: $0) == i } ?? false
    }

    public func shown(open: Set<Int>) -> [Int] {
        entries.indices.filter { i in owner(of: i).map(open.contains) ?? true }
    }

    public func marked(_ current: Int?, open: Set<Int>) -> Int? {
        guard let current else { return nil }
        guard let owner = owner(of: current), !open.contains(owner) else { return current }
        return owner
    }

    public func indent(_ i: Int) -> Int {
        let levels = Set(entries.map(\.level)).sorted()
        return levels.firstIndex(of: entries[i].level) ?? 0
    }

    public static func isContents(_ paragraph: Paragraph) -> Bool {
        paragraph.childCount > 0 && paragraph.plainText.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("[TOC]") == .orderedSame
    }
}
