import Foundation

public struct LectureSplit: Equatable, Sendable {
    public enum Match: String, Codable, Sendable {
        case name
        case claude
    }

    public struct Section: Equatable, Sendable, Identifiable {
        public var id: UUID
        public var title: String
        public var firstPage: Int
        public var lastPage: Int
        public var unit: UUID?
        public var isNew: Bool
        public var parent: UUID?
        public var match: Match?

        public init(
            id: UUID = UUID(), title: String, firstPage: Int, lastPage: Int, unit: UUID? = nil, isNew: Bool = false,
            parent: UUID? = nil, match: Match? = nil
        ) {
            self.id = id
            self.title = title
            self.firstPage = firstPage
            self.lastPage = lastPage
            self.unit = unit
            self.isNew = isNew
            self.parent = parent
            self.match = match
        }

        public var pages: ClosedRange<Int> { firstPage...lastPage }
    }

    public let pageCount: Int
    public private(set) var sections: [Section]

    public init(pageCount: Int) {
        self.pageCount = max(pageCount, 1)
        sections = [Section(title: "", firstPage: 1, lastPage: self.pageCount)]
    }

    public init?(_ found: [Section], pageCount: Int) {
        let count = max(pageCount, 1)
        let starts = found.filter { $0.firstPage <= count }.sorted { $0.firstPage < $1.firstPage }
        var tidy: [Section] = []
        for var s in starts {
            s.firstPage = max(s.firstPage, 1)
            if let last = tidy.last, s.firstPage <= last.firstPage { s.firstPage = last.firstPage + 1 }
            guard s.firstPage <= count else { continue }
            tidy.append(s)
        }

        guard !tidy.isEmpty else { return nil }
        tidy[0].firstPage = 1
        for i in tidy.indices {
            tidy[i].lastPage = i + 1 < tidy.count ? tidy[i + 1].firstPage - 1 : count
        }
        self.pageCount = count
        sections = tidy
    }

    public init(file: CourseFile, material: UUID, pageCount: Int) {
        let zones = file.lectureZones(of: material, pageCount: pageCount)
        guard !zones.isEmpty else {
            self.init(pageCount: pageCount)
            return
        }
        let titles = Dictionary(keepingFirst: file.units.map { ($0.id, $0.title) })
        self.init(
            sections: zones.map { zone in
                Section(
                    title: zone.units.first.flatMap { titles[$0] } ?? "", firstPage: zone.firstPage, lastPage: zone.lastPage,
                    unit: zone.units.first)
            }, pageCount: pageCount)
    }

    private init(sections: [Section], pageCount: Int) {
        self.pageCount = max(pageCount, 1)
        self.sections = sections
    }

    public func section(at page: Int) -> Int {
        sections.firstIndex { $0.pages.contains(page) } ?? (page < 1 ? 0 : sections.count - 1)
    }

    @discardableResult
    public mutating func moveBoundary(after i: Int, to lastPage: Int) -> Int {
        guard sections.indices.contains(i), sections.indices.contains(i + 1) else { return lastPage }
        let edge = min(max(lastPage, sections[i].firstPage), sections[i + 1].lastPage - 1)
        sections[i].lastPage = edge
        sections[i + 1].firstPage = edge + 1
        return edge
    }

    public func boundaryRange(after i: Int) -> ClosedRange<Int>? {
        guard sections.indices.contains(i), sections.indices.contains(i + 1) else { return nil }
        return sections[i].firstPage...(sections[i + 1].lastPage - 1)
    }

    @discardableResult
    public mutating func split(at page: Int, title: String = "") -> Int? {
        let i = section(at: page)
        guard page > sections[i].firstPage, page <= sections[i].lastPage else { return nil }
        let tail = Section(title: title, firstPage: page, lastPage: sections[i].lastPage)
        sections[i].lastPage = page - 1
        sections.insert(tail, at: i + 1)
        return i + 1
    }

    public mutating func merge(after i: Int) {
        guard sections.indices.contains(i), sections.indices.contains(i + 1) else { return }
        sections[i].lastPage = sections[i + 1].lastPage
        sections.remove(at: i + 1)
    }

    @discardableResult
    public mutating func moveEdge(of i: Int, to page: Int) -> Int {
        guard sections.indices.contains(i) else { return i }
        let page = min(max(page, 1), pageCount)
        if page >= sections[i].firstPage {
            if sections.indices.contains(i + 1) {
                moveBoundary(after: i, to: page)
            } else if page < sections[i].lastPage {
                split(at: page + 1)
            }
        } else if i > 0 {
            moveBoundary(after: i - 1, to: page - 1)
        }
        return i
    }

    // `pages` 뒤에 남은 쪽은 그대로 둔다. `split(at:)`을 쓰면 그 쪽이 단원을 잃고, 구획 안에서 끝나는 범위가 그 구획의
    // 나머지를 조용히 단원에서 빼기 때문이다.
    @discardableResult
    public mutating func carve(_ pages: ClosedRange<Int>) -> Int {
        let lo = min(max(pages.lowerBound, 1), pageCount), hi = min(max(pages.upperBound, lo), pageCount)
        if hi < pageCount {
            let j = section(at: hi + 1)
            if sections[j].firstPage <= hi {
                var rest = sections[j]
                rest.firstPage = hi + 1
                if sections[j].firstPage <= lo { rest.id = UUID() }
                sections[j].lastPage = hi
                sections.insert(rest, at: j + 1)
            }
        }

        split(at: lo)
        let first = section(at: lo)
        while sections.indices.contains(first + 1), sections[first + 1].lastPage <= hi { merge(after: first) }
        return first
    }

    public mutating func setUnit(_ unit: UUID?, of i: Int, match: Match? = nil) {
        guard sections.indices.contains(i) else { return }
        sections[i].unit = unit
        sections[i].isNew = false
        sections[i].parent = nil
        sections[i].match = match
    }

    // 이미 단원을 만드는 구획은 ID를 지키므로, 나중에 제목을 고쳐도 단원이 둘 생기지 않는다.
    public mutating func makeNew(_ i: Int, parent: UUID? = nil) {
        guard sections.indices.contains(i) else { return }
        if !sections[i].isNew { sections[i].unit = UUID() }
        sections[i].isNew = true
        sections[i].parent = parent
        sections[i].match = nil
    }

    public mutating func rename(_ i: Int, to title: String) {
        guard sections.indices.contains(i) else { return }
        sections[i].title = title
    }

    public var cuts: [LectureCut] {
        var out: [LectureCut] = []
        for s in sections {
            guard let unit = s.unit else { continue }
            let title = s.title.trimmingCharacters(in: .whitespaces)
            if s.isNew && title.isEmpty { continue }
            if let last = out.last, last.unit == unit, last.lastPage + 1 == s.firstPage {
                out[out.count - 1].lastPage = s.lastPage
            } else {
                out.append(
                    LectureCut(
                        unit: unit, title: s.isNew ? title : nil, parent: s.isNew ? s.parent : nil, firstPage: s.firstPage,
                        lastPage: s.lastPage))
            }
        }
        return out
    }

    public var claimed: Int { sections.count { $0.unit != nil && !($0.isNew && $0.title.trimmingCharacters(in: .whitespaces).isEmpty) } }
}
