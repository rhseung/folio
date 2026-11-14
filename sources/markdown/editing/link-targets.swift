import Foundation
import Markdown

extension WikiLink {
    // 대괄호와 `|`는 링크를 일찍 끝내므로 이름에 넣지 않는다.
    public static func written(_ kind: String, _ id: UUID, fragment: String? = nil, alias: String? = nil, embed: Bool = false) -> String {
        let part = fragment.map { "#" + $0 } ?? ""
        return (embed ? "!" : "") + "[[\(kind):\(id.uuidString)\(part)\(aliasPart(alias))]]"
    }

    public static func written(address: String, alias: String? = nil) -> String {
        "[[\(address)\(aliasPart(alias))]]"
    }

    static func aliasPart(_ alias: String?) -> String {
        let name = alias.map { a in
            a.split(whereSeparator: { "[]|".contains($0) || $0.isWhitespace }).joined(separator: " ")
        }
        return name.flatMap { $0.isEmpty ? nil : "|" + $0 } ?? ""
    }

    public static func pastesAsLink(in text: NSString, at caret: Int) -> Bool {
        guard SourcePlace.at(caret, in: text) == .text else { return false }
        let line = text.lineRange(for: NSRange(location: caret, length: 0))
        let prefix = text.substring(with: NSRange(location: line.location, length: caret - line.location))
        return prefix.firstMatch(of: #/\[\[[^\]]*$/#) == nil && prefix.firstMatch(of: #/\]\([^)\s]*$/#) == nil && !prefix.hasSuffix("<")
    }

    public static func linkable(heading: String) -> Bool {
        !heading.isEmpty && !heading.contains { "[]|#\n".contains($0) }
    }
}

extension ParsedNote {
    public struct HeadingLine: Equatable, Sendable {
        public var level: Int
        public var text: String
    }

    public struct LinkableBlock: Equatable, Sendable {
        public var line: Int
        public var excerpt: String
        public var id: String?
    }

    public var headings: [HeadingLine] {
        NoteOutline.headings(in: document).compactMap { h in
            let text = NoteOutline.anchor(of: h)
            return text.isEmpty ? nil : HeadingLine(level: h.level, text: text)
        }
    }

    // 목록 항목의 ID는 항목 자기 글 뒤, 하위 목록 앞에 둔다. 그래야 `blockSource`가 하위 목록의 마지막 항목이 아니라
    // 이 항목으로 읽는다.
    public var linkableBlocks: [LinkableBlock] {
        var out: [LinkableBlock] = []
        func add(_ lines: ClosedRange<Int>?) {
            guard let lines else { return }
            let last = bodyLines[lines.upperBound - 1].trimmingCharacters(in: .whitespaces)
            // 그 줄이 수식이나 펜스를 닫는다면, 뒤에 ID가 붙은 뒤로는 더는 닫지 못한다.
            guard !last.hasSuffix("$$"), !last.hasSuffix("```"), !last.hasSuffix("~~~") else { return }
            let first = BlockID.strip(String(bodyLines[lines.lowerBound - 1])).text
            let excerpt = first.replacing(
                #/^[ \t>]*(?:\[![A-Za-z-]+\][+-]?[ \t]*)?(?:(?:[-*+]|\d+[.)])[ \t]+(?:\[[ xX]\][ \t]+)?)?/#, with: ""
            )
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
