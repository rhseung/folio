import Foundation

// MARK: Reading a lecture

public enum LectureReading {
    public struct Bookmark: Equatable, Sendable {
        public var title: String
        public var page: Int
        public var depth: Int

        public init(title: String, page: Int, depth: Int = 0) {
            self.title = title
            self.page = page
            self.depth = depth
        }
    }

    public struct Page: Equatable, Sendable {
        public var title: String?
        public var words: Int

        public init(title: String?, words: Int) {
            self.title = title
            self.words = words
        }
    }

    public static func sections(outline: [Bookmark], pageCount: Int) -> [LectureSplit.Section]? {
        let usable = outline.filter { (1...max(pageCount, 1)).contains($0.page) && !clean($0.title).isEmpty }
        for depth in Set(usable.map(\.depth)).sorted() {
            let level = usable.filter { $0.depth == depth }
            guard Set(level.map(\.page)).count >= 2 else { continue }
            guard level.count <= max(pageCount / 2, 2) else { return nil }
            return level.map { LectureSplit.Section(title: clean($0.title), firstPage: $0.page, lastPage: $0.page) }
        }
        return nil
    }

    public static func sections(pages: [Page], units: [String]) -> [LectureSplit.Section]? {
        var found: [LectureSplit.Section] = []
        var previous: String?
        for (i, page) in pages.enumerated() {
            let title = page.title.map(clean) ?? ""
            defer { previous = key(title) }
            guard !title.isEmpty, key(title) != previous else { continue }
            let names = SectionMatch.unit(for: title, in: units) != nil
            let divider = i > 0 && page.words <= dividerWords
            if i == 0 || names || divider {
                found.append(LectureSplit.Section(title: title, firstPage: i + 1, lastPage: i + 1))
            }
        }
        guard found.count >= 2, found.count <= max(pages.count / 3, 2) else { return nil }
        return found
    }

    static let dividerWords = 8

    public static func clean(_ title: String) -> String {
        var t = title.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacing(/(?i)\s*[\(\[]?\s*(cont(inued|'d|\.)?|계속)\s*[\)\]]?\s*$/, with: "")
        t = t.replacing(/\s*\(\d+\)\s*$/, with: "")
        t = t.replacing(/^(?i)(part|chapter|lecture|section|ch\.?|§)\s*\d+[\.:)\-–]?\s*/, with: "")
        t = t.replacing(/^\d+(\.\d+)*[\.:)]?\s+/, with: "")
        return t.trimmingCharacters(in: CharacterSet(charactersIn: " :-–—"))
    }

    static func key(_ title: String) -> String { SectionMatch.key(title) }
}
