import Foundation

public struct UnitPages: Codable, Sendable, Hashable {
    public var materialId: UUID
    public var firstPage: Int
    public var lastPage: Int

    public init(materialId: UUID, firstPage: Int, lastPage: Int) {
        self.materialId = materialId
        self.firstPage = firstPage
        self.lastPage = lastPage
    }

    public var pages: ClosedRange<Int> { min(firstPage, lastPage)...max(firstPage, lastPage) }
}

extension Unit {
    var lectureMaterialIds: [UUID] {
        get { lecturePages.map(\.materialId) }
        set { lecturePages = lecturePages.filter { newValue.contains($0.materialId) } }
    }
}

public struct LectureZone: Equatable, Sendable {
    public var firstPage: Int
    public var lastPage: Int
    public var units: [UUID]

    public init(firstPage: Int, lastPage: Int, units: [UUID]) {
        self.firstPage = firstPage
        self.lastPage = lastPage
        self.units = units
    }

    public var pages: ClosedRange<Int> { firstPage...lastPage }
}

extension CourseFile {
    public func unitPages(of material: UUID) -> [(unit: Unit, pages: ClosedRange<Int>)] {
        UnitTree.outline(units).flatMap { item in
            item.unit.lecturePages.filter { $0.materialId == material }.map { (item.unit, $0.pages) }
        }
    }

    public func isSplit(_ material: UUID) -> Bool {
        units.contains { $0.lecturePages.contains { $0.materialId == material } }
    }

    public func lectureZones(of material: UUID, pageCount: Int?) -> [LectureZone] {
        let held = unitPages(of: material)
        guard let reach = held.map(\.pages.upperBound).max() else { return [] }
        let end = pageCount ?? reach
        guard end > 0 else { return [] }

        var zones: [LectureZone] = []
        for page in 1...end {
            var here: [UUID] = []
            for (unit, pages) in held where pages.contains(page) && !here.contains(unit.id) { here.append(unit.id) }
            if let last = zones.last, last.units == here {
                zones[zones.count - 1].lastPage = page
            } else {
                zones.append(LectureZone(firstPage: page, lastPage: page, units: here))
            }
        }
        return zones
    }

    public func units(in material: UUID, meeting pages: ClosedRange<Int>) -> [Unit] {
        let met = unitPages(of: material).filter { $0.pages.overlaps(pages) }
        var seen: Set<UUID> = []
        // 안정 정렬이어야 같은 쪽에서 시작하는 단원이 목차 순서를 지킨다.
        return met.enumerated().sorted { ($0.element.pages.lowerBound, $0.offset) < ($1.element.pages.lowerBound, $1.offset) }
            .map(\.element.unit).filter { seen.insert($0.id).inserted }
    }

    public func splitProgress(of session: Session) -> (material: UUID, pages: ClosedRange<Int>)? {
        session.materials.lazy.compactMap { link in link.pages.flatMap { self.isSplit(link.materialId) ? (link.materialId, $0) : nil } }
            .first
    }

    public func pages(of unit: UUID, in material: UUID) -> ClosedRange<Int>? {
        let held = units.first { $0.id == unit }?.lecturePages.filter { $0.materialId == material } ?? []
        guard let lo = held.map(\.pages.lowerBound).min(), let hi = held.map(\.pages.upperBound).max() else { return nil }
        return lo...hi
    }

    public func sectionLabel(of material: UUID, pages: ClosedRange<Int>) -> String? {
        let reached = units(in: material, meeting: pages)
        guard let first = reached.first, let last = reached.last else { return nil }
        return first.id == last.id ? first.title : "\(first.title)–\(last.title)"
    }
}

// MARK: Splitting a file

public struct LectureCut: Codable, Sendable, Hashable {
    public var unit: UUID
    public var title: String?
    public var parent: UUID?
    public var firstPage: Int
    public var lastPage: Int

    public init(unit: UUID, title: String? = nil, parent: UUID? = nil, firstPage: Int, lastPage: Int) {
        self.unit = unit
        self.title = title
        self.parent = parent
        self.firstPage = firstPage
        self.lastPage = lastPage
    }
}

extension CourseFile {
    public mutating func split(_ material: UUID, into cuts: [LectureCut], device: DeviceID, now: Date) {
        for i in units.indices where units[i].lecturePages.contains(where: { $0.materialId == material }) {
            units[i].lecturePages.removeAll { $0.materialId == material }
            units[i].touch(by: device, at: now)
        }

        for cut in cuts {
            if !units.contains(where: { $0.id == cut.unit }) {
                guard let title = cut.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { continue }
                let parent = cut.parent.flatMap { p in units.contains { $0.id == p } ? p : nil }
                units.append(
                    Unit(
                        id: cut.unit, device: device, at: now, title: title, order: UnitTree.nextOrder(under: parent, in: units),
                        parentId: parent))
            }
            guard let u = units.firstIndex(where: { $0.id == cut.unit }) else { continue }
            units[u].lecturePages.append(UnitPages(materialId: material, firstPage: cut.firstPage, lastPage: cut.lastPage))
            units[u].touch(by: device, at: now)
        }
    }
}

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

public enum SectionMatch {
    public static func unit(for title: String, in units: [Unit]) -> Unit? {
        unit(for: title, in: units.map(\.title)).map { units[$0] }
    }

    public static func unit(for title: String, in titles: [String]) -> Int? {
        let found = key(LectureReading.clean(title))
        guard !found.isEmpty else { return nil }
        let keys = titles.map { key(LectureReading.clean($0)) }
        if let exact = keys.firstIndex(of: found) { return exact }
        let holding = keys.indices.filter { i in
            let k = keys[i]
            return k.count > 2 && found.count > 2 && (found.contains(k) || k.contains(found))
        }
        return holding.max { keys[$0].count < keys[$1].count }
    }

    static func key(_ title: String) -> String {
        title.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    public static func match(_ split: LectureSplit, units: [Unit]) -> LectureSplit {
        var out = split
        for i in out.sections.indices {
            if let unit = unit(for: out.sections[i].title, in: units) {
                out.setUnit(unit.id, of: i, match: .name)
            } else {
                out.makeNew(i)
            }
        }
        return out
    }
}
