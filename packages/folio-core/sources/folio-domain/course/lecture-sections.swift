import Foundation

/// Pages of one lecture file that belong to a unit.
public struct UnitPages: Codable, Sendable, Hashable {
    public var materialId: UUID
    public var firstPage: Int
    public var lastPage: Int

    public init(materialId: UUID, firstPage: Int, lastPage: Int) {
        self.materialId = materialId
        self.firstPage = firstPage
        self.lastPage = lastPage
    }

    /// In order even when a hand edit wrote it backwards; the model refuses that on save.
    public var pages: ClosedRange<Int> { min(firstPage, lastPage)...max(firstPage, lastPage) }
}

extension Unit {
    /// The unit's lecture files as ids, so the model treats them like any other list of pointers. Setting it keeps only
    /// the pages of files still listed.
    var lectureMaterialIds: [UUID] {
        get { lecturePages.map(\.materialId) }
        set { lecturePages = lecturePages.filter { newValue.contains($0.materialId) } }
    }
}

/// A stretch of a lecture file that the same units hold. Without units it is pages no unit takes: an unnamed zone.
public struct LectureZone: Equatable, Sendable {
    public var firstPage: Int
    public var lastPage: Int
    /// In outline order. More than one where units' pages overlap.
    public var units: [UUID]

    public init(firstPage: Int, lastPage: Int, units: [UUID]) {
        self.firstPage = firstPage
        self.lastPage = lastPage
        self.units = units
    }

    public var pages: ClosedRange<Int> { firstPage...lastPage }
}

extension CourseFile {
    /// Every unit's pages of `material`, units in outline order.
    public func unitPages(of material: UUID) -> [(unit: Unit, pages: ClosedRange<Int>)] {
        UnitTree.outline(units).flatMap { item in
            item.unit.lecturePages.filter { $0.materialId == material }.map { (item.unit, $0.pages) }
        }
    }

    /// Whether any unit takes pages of `material`. A file no unit splits keeps the plain page bar.
    public func isSplit(_ material: UUID) -> Bool {
        units.contains { $0.lecturePages.contains { $0.materialId == material } }
    }

    /// The file cut where the units holding its pages change, through `pageCount` (without it, the last page a unit
    /// holds). Pages past the count are dropped, as a range typed too long shouldn't make the file look longer. Empty for
    /// a file no unit splits: it has no zones, named or not.
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

    /// Units whose pages of `material` meet `pages`, in the order the file reaches them.
    public func units(in material: UUID, meeting pages: ClosedRange<Int>) -> [Unit] {
        let met = unitPages(of: material).filter { $0.pages.overlaps(pages) }
        var seen: Set<UUID> = []
        // Stable, so units starting on one page keep the outline's order.
        return met.enumerated().sorted { ($0.element.pages.lowerBound, $0.offset) < ($1.element.pages.lowerBound, $1.offset) }
            .map(\.element.unit).filter { seen.insert($0.id).inserted }
    }

    /// A class's pages in its first lecture file the units split: what its progress line draws as the section bar's
    /// small form instead of joining unit titles. Nil when no such file has a range for it.
    public func splitProgress(of session: Session) -> (material: UUID, pages: ClosedRange<Int>)? {
        session.materials.lazy.compactMap { link in link.pages.flatMap { self.isSplit(link.materialId) ? (link.materialId, $0) : nil } }.first
    }

    /// The span of a unit's pages in `material`, first to last: a unit page's line for that file.
    public func pages(of unit: UUID, in material: UUID) -> ClosedRange<Int>? {
        let held = units.first { $0.id == unit }?.lecturePages.filter { $0.materialId == material } ?? []
        guard let lo = held.map(\.pages.lowerBound).min(), let hi = held.map(\.pages.upperBound).max() else { return nil }
        return lo...hi
    }

    /// What a range of the file reads as on its bar: the first and last unit it reaches (`König–Hall`), or the one.
    public func sectionLabel(of material: UUID, pages: ClosedRange<Int>) -> String? {
        let reached = units(in: material, meeting: pages)
        guard let first = reached.first, let last = reached.last else { return nil }
        return first.id == last.id ? first.title : "\(first.title)–\(last.title)"
    }
}

// MARK: Splitting a file

/// One approved section of a lecture file, as `material split` and `material import` write it. A unit that doesn't
/// exist yet is made from `title` (under `parent`) with this id, so two cuts can name one new unit.
public struct LectureCut: Codable, Sendable, Hashable {
    public var unit: UUID
    /// The title of a unit to make; left alone for a unit that exists.
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
    /// Every unit's pages of `material` become exactly `cuts`: pages a cut doesn't name belong to no unit afterwards.
    /// Units a cut names that don't exist are made first, in the order of the cuts. A cut without a title naming no
    /// unit is skipped; the action refuses it before calling this.
    public mutating func split(_ material: UUID, into cuts: [LectureCut], device: DeviceID, now: Date) {
        for i in units.indices where units[i].lecturePages.contains(where: { $0.materialId == material }) {
            units[i].lecturePages.removeAll { $0.materialId == material }
            units[i].touch(by: device, at: now)
        }
        for cut in cuts {
            if !units.contains(where: { $0.id == cut.unit }) {
                guard let title = cut.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { continue }
                let parent = cut.parent.flatMap { p in units.contains { $0.id == p } ? p : nil }
                units.append(Unit(id: cut.unit, device: device, at: now, title: title, order: UnitTree.nextOrder(under: parent, in: units), parentId: parent))
            }
            guard let u = units.firstIndex(where: { $0.id == cut.unit }) else { continue }
            units[u].lecturePages.append(UnitPages(materialId: material, firstPage: cut.firstPage, lastPage: cut.lastPage))
            units[u].touch(by: device, at: now)
        }
    }
}

/// One file's pages cut into consecutive sections, each for a unit or for none: what the split editor and the add
/// sheet hold until the user approves it. Every edit keeps the sections in page order, touching, each at least one
/// page, and together the whole file.
public struct LectureSplit: Equatable, Sendable {
    /// Why a section points at its unit, for its tooltip.
    public enum Match: String, Codable, Sendable {
        /// The PDF's outline or slide title is the unit's name.
        case name
        /// Claude put the section under the unit.
        case claude
    }

    public struct Section: Equatable, Sendable, Identifiable {
        public var id: UUID
        /// What the file calls it (an outline entry, a slide title); a new unit's title.
        public var title: String
        public var firstPage: Int
        public var lastPage: Int
        /// Nil: the pages go to no unit.
        public var unit: UUID?
        /// The unit is made on approval, from `title`.
        public var isNew: Bool
        public var parent: UUID?
        public var match: Match?

        public init(id: UUID = UUID(), title: String, firstPage: Int, lastPage: Int, unit: UUID? = nil, isNew: Bool = false,
                    parent: UUID? = nil, match: Match? = nil) {
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

    /// The whole file as one section for no unit: where splitting by hand starts.
    public init(pageCount: Int) {
        self.pageCount = max(pageCount, 1)
        sections = [Section(title: "", firstPage: 1, lastPage: self.pageCount)]
    }

    /// Found sections tidied into a split: sorted, cut to the file, gaps given to the section before, the first one
    /// starting on page 1. Nil when nothing usable is left.
    public init?(_ found: [Section], pageCount: Int) {
        let count = max(pageCount, 1)
        let starts = found.filter { $0.firstPage <= count }.sorted { $0.firstPage < $1.firstPage }
        var tidy: [Section] = []
        for var s in starts {
            s.firstPage = max(s.firstPage, 1)
            // Two sections starting on one page: the later one only begins after it.
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

    /// The split the course already holds for `material`: one section per zone, with the zone's first unit (an
    /// overlap the editor can't show is narrowed to that unit when saved).
    public init(file: CourseFile, material: UUID, pageCount: Int) {
        let zones = file.lectureZones(of: material, pageCount: pageCount)
        guard !zones.isEmpty else {
            self.init(pageCount: pageCount)
            return
        }
        let titles = Dictionary(keepingFirst: file.units.map { ($0.id, $0.title) })
        self.init(sections: zones.map { zone in
            Section(title: zone.units.first.flatMap { titles[$0] } ?? "", firstPage: zone.firstPage, lastPage: zone.lastPage, unit: zone.units.first)
        }, pageCount: pageCount)
    }

    private init(sections: [Section], pageCount: Int) {
        self.pageCount = max(pageCount, 1)
        self.sections = sections
    }

    /// The section holding `page`.
    public func section(at page: Int) -> Int {
        sections.firstIndex { $0.pages.contains(page) } ?? (page < 1 ? 0 : sections.count - 1)
    }

    /// Moves the boundary after section `i` so that section ends on `lastPage`, kept so both sides keep a page.
    /// Returns where it landed.
    @discardableResult
    public mutating func moveBoundary(after i: Int, to lastPage: Int) -> Int {
        guard sections.indices.contains(i), sections.indices.contains(i + 1) else { return lastPage }
        let edge = min(max(lastPage, sections[i].firstPage), sections[i + 1].lastPage - 1)
        sections[i].lastPage = edge
        sections[i + 1].firstPage = edge + 1
        return edge
    }

    /// The pages a boundary after section `i` can move through.
    public func boundaryRange(after i: Int) -> ClosedRange<Int>? {
        guard sections.indices.contains(i), sections.indices.contains(i + 1) else { return nil }
        return sections[i].firstPage...(sections[i + 1].lastPage - 1)
    }

    /// A new section from `page` on, cut off the section holding it. It names no unit yet. Nil when `page` already
    /// starts a section.
    @discardableResult
    public mutating func split(at page: Int, title: String = "") -> Int? {
        let i = section(at: page)
        guard page > sections[i].firstPage, page <= sections[i].lastPage else { return nil }
        let tail = Section(title: title, firstPage: page, lastPage: sections[i].lastPage)
        sections[i].lastPage = page - 1
        sections.insert(tail, at: i + 1)
        return i + 1
    }

    /// Section `i + 1` joins section `i`, which keeps its title and unit.
    public mutating func merge(after i: Int) {
        guard sections.indices.contains(i), sections.indices.contains(i + 1) else { return }
        sections[i].lastPage = sections[i + 1].lastPage
        sections.remove(at: i + 1)
    }

    /// A page picked while section `i` is being changed (⇧-click in the thumbnails, a tap on a touch screen), as a
    /// class's progress is changed in the page strip: at or after its start it moves the end there, before it the
    /// start. The neighbor on that side gives or takes the pages and keeps at least one. The last section has no
    /// neighbor to give its end pages to, so they become a section for no unit. Returns where section `i` now is.
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

    /// `pages` as one section: cut where they start and after where they end, and every section between joined into the
    /// first. It keeps that section's unit when `pages` start where it does; cut out of a section's middle, it goes to
    /// no unit, as a cut's tail does. The pages left after `pages` stay what they were: `split(at:)` would give them to
    /// no unit, and a range ending inside a section would quietly take the rest of that section out of its unit.
    /// Returns its index.
    @discardableResult
    public mutating func carve(_ pages: ClosedRange<Int>) -> Int {
        let lo = min(max(pages.lowerBound, 1), pageCount), hi = min(max(pages.upperBound, lo), pageCount)
        if hi < pageCount {
            let j = section(at: hi + 1)
            if sections[j].firstPage <= hi {
                var rest = sections[j]
                rest.firstPage = hi + 1
                // Its id goes with it unless the pages before keep that section on: a section joined into the range
                // is gone, but one cut at `lo` or starting the range stays.
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

    /// Section `i` makes a unit of its own title on approval. A section that already makes one keeps its id, so a
    /// title edited after doesn't make a second unit.
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

    /// What approving writes: one cut per run of sections for one unit, so touching sections of a unit stay one range.
    /// A new unit without a title can't be made and is left out.
    public var cuts: [LectureCut] {
        var out: [LectureCut] = []
        for s in sections {
            guard let unit = s.unit else { continue }
            let title = s.title.trimmingCharacters(in: .whitespaces)
            if s.isNew && title.isEmpty { continue }
            if let last = out.last, last.unit == unit, last.lastPage + 1 == s.firstPage {
                out[out.count - 1].lastPage = s.lastPage
            } else {
                out.append(LectureCut(unit: unit, title: s.isNew ? title : nil, parent: s.isNew ? s.parent : nil, firstPage: s.firstPage, lastPage: s.lastPage))
            }
        }
        return out
    }

    /// Sections that go to a unit, new or not: the add sheet's "단원 n구역".
    public var claimed: Int { sections.count { $0.unit != nil && !($0.isNew && $0.title.trimmingCharacters(in: .whitespaces).isEmpty) } }
}

// MARK: Reading a lecture

/// Finds a lecture's sections in what the app reads from its PDF: the outline (bookmarks) first, then each page's
/// title. Only a proposal: the add sheet shows it, and nothing is written until the user approves (#321).
public enum LectureReading {
    /// One bookmark: its title, the 1-based page it opens and how deep it sits.
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

    /// What a page says: its title (the largest line near the top) and how many words the rest has.
    public struct Page: Equatable, Sendable {
        public var title: String?
        public var words: Int

        public init(title: String?, words: Int) {
            self.title = title
            self.words = words
        }
    }

    /// The outline's shallowest level that splits the file in two or more: a deck's chapters rather than every slide.
    /// Nil when the outline says nothing that way, so slide titles are tried next.
    public static func sections(outline: [Bookmark], pageCount: Int) -> [LectureSplit.Section]? {
        let usable = outline.filter { (1...max(pageCount, 1)).contains($0.page) && !clean($0.title).isEmpty }
        for depth in Set(usable.map(\.depth)).sorted() {
            let level = usable.filter { $0.depth == depth }
            guard Set(level.map(\.page)).count >= 2 else { continue }
            // One bookmark per slide is no outline at all.
            guard level.count <= max(pageCount / 2, 2) else { return nil }
            return level.map { LectureSplit.Section(title: clean($0.title), firstPage: $0.page, lastPage: $0.page) }
        }
        return nil
    }

    /// Sections from page titles: a new one starts at a page whose title names one of `units`, or at a divider (a page
    /// with its title and almost nothing else) after the first page. Nil when that finds no second section or too many
    /// to be chapters, so the caller asks Claude.
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

    /// Words besides the title that a section's title slide may still carry (a subtitle, the lecturer's name).
    static let dividerWords = 8

    /// `Part 2: Hall's theorem (cont.)` → `Hall's theorem`: the numbering in front and a continuation mark after are the
    /// deck's, not the section's.
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

/// Which unit a found title belongs to, by name.
public enum SectionMatch {
    /// The unit whose title is the found one, ignoring case, spacing and numbering; failing that, the longest title
    /// that holds the other (`Hall` in `Hall's theorem`). Titles of two letters or fewer match only exactly.
    public static func unit(for title: String, in units: [Unit]) -> Unit? {
        unit(for: title, in: units.map(\.title)).map { units[$0] }
    }

    /// Index into `titles`.
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

    /// Each found section matched to a unit by name, or else proposed as a new unit of its title.
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
