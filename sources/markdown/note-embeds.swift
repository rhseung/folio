import Foundation
import Markdown

public struct NoteEmbeds {
    public struct Note {
        public var key: String
        public var text: String
        public var math: String?

        public init(key: String, text: String, math: String? = nil) {
            self.key = key
            self.text = text
            self.math = math
        }
    }

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

    public var key: String?
    public var labels: Labels
    public var find: (WikiLink) -> Note?
    // `find`와 따로 둔다. `find`는 그릴 수 있는 노트만 돌려주지만, LaTeX 노트로 가는 링크도 제목을 찾아야 한다.
    public var title: (UUID) -> String?
    // 앱이 링크를 열 때와 같은 방법으로 찾아야, 온전히 그린 링크는 항상 열리고 깨진 링크로 그린 것은 열리지 않는다.
    public var hasNote: (String) -> Bool
    public var name: (String) -> String?

    public init(
        key: String?, labels: Labels, title: @escaping (UUID) -> String? = { _ in nil },
        hasNote: @escaping (String) -> Bool = { _ in true },
        name: @escaping (String) -> String? = { _ in nil }, find: @escaping (WikiLink) -> Note?
    ) {
        self.key = key
        self.labels = labels
        self.title = title
        self.hasNote = hasNote
        self.name = name
        self.find = find
    }

    // 고리는 키로 막지만, 고리 없이 서로 임베드하는 노트들이 과목 전체를 한 페이지에 그릴 수 있어서 깊이를 제한한다.
    public static let depth = 4
}

extension WikiLink {
    // 확장자는 글자로 시작해야 하므로 `v1.2` 같은 제목은 노트로 읽는다.
    var namesNote: Bool {
        if isAppLink { return objectKind == "note" }
        let ext = (target as NSString).pathExtension
        return ext.lowercased() == "md" || ext.wholeMatch(of: /[A-Za-z][A-Za-z0-9]{0,4}/) == nil
    }

    func key(in note: String) -> String {
        note + (blockID.map { "#^" + $0 } ?? fragment.map { "#" + $0 } ?? "")
    }
}

extension ParsedNote {
    public func section(heading: String?, block: String?) -> String? {
        if let block { return blockSource(block) }
        if let heading { return headingSection(heading) }
        return body
    }

    func headingSection(_ heading: String) -> String? {
        let tops = Array(document.children)
        guard let i = headingIndex(heading, in: tops), let level = (tops[i] as? Heading)?.level,
            let start = lines(of: tops[i])?.lowerBound
        else { return nil }
        let next = tops[(i + 1)...].first { ($0 as? Heading).map { $0.level <= level } ?? false }
        var end = next.flatMap { lines(of: $0)?.lowerBound }.map { $0 - 1 } ?? bodyLines.count
        while end > start, bodyLines[end - 1].allSatisfy(\.isWhitespace) { end -= 1 }
        return source(start...end)
    }

    func blockSource(_ id: String) -> String? {
        guard let (range, item) = blockLines(id) else { return nil }
        guard let lines = item else { return source(range) }
        let rows = bodyLines[(lines.lowerBound - 1)...(lines.upperBound - 1)]
        let indent = rows.first?.prefix(while: { $0 == " " || $0 == "\t" }).count ?? 0
        return rows.map { String($0.dropFirst(min(indent, $0.prefix(while: { $0 == " " || $0 == "\t" }).count))) }.joined(separator: "\n")
    }

    func headingIndex(_ heading: String, in tops: [Markup]) -> Int? {
        let wanted = heading.trimmingCharacters(in: .whitespaces)
        return tops.firstIndex { node in
            guard let h = node as? Heading else { return false }
            let text = NoteOutline.anchor(of: h)
            return text.caseInsensitiveCompare(wanted) == .orderedSame || HTMLRenderer.slug(text) == HTMLRenderer.slug(wanted)
        }
    }

    func blockLines(_ id: String) -> (top: ClosedRange<Int>, item: ClosedRange<Int>?)? {
        guard let line = bodyLines.firstIndex(where: { $0.firstMatch(of: BlockID.pattern).map { String($0.1) } == id }).map({ $0 + 1 }),
            let top = document.children.first(where: { lines(of: $0)?.contains(line) ?? false }),
            let range = lines(of: top)
        else { return nil }
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
