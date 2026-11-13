import Foundation

/// Pages of one lecture file that the same classes went through, in page order.
public struct LectureSpan: Equatable, Sendable {
    public var firstPage: Int
    public var lastPage: Int
    /// In class order. Empty: no class has reached these pages.
    public var sessions: [UUID]

    public init(firstPage: Int, lastPage: Int, sessions: [UUID]) {
        self.firstPage = firstPage
        self.lastPage = lastPage
        self.sessions = sessions
    }
}

/// A start and an end page edited together, either one possibly empty. Every move keeps both within the file and
/// the start at or before the end: moving one end past the other pushes it along, so a one-page range is reachable
/// from either side and the range never runs backwards.
public struct PageRange: Equatable, Sendable {
    public enum End: Sendable { case first, last }

    public var first: Int?
    public var last: Int?

    public init(first: Int? = nil, last: Int? = nil) {
        self.first = first
        self.last = last
    }

    /// Pages a field may take: the file's, or any page while its count isn't known yet.
    public static func bounds(_ pages: Int?) -> ClosedRange<Int> { 1...max(pages ?? 9_999, 1) }

    public subscript(end: End) -> Int? { end == .first ? first : last }

    /// The end set when the other isn't: a range only half picked, whose one handle drags out the other end
    /// (`tapping` from it) rather than moving away from it.
    public var lone: End? {
        switch (first, last) {
        case (_?, nil): .first
        case (nil, _?): .last
        default: nil
        }
    }

    /// The run of pages around `page` that no range in `taken` holds, within the file. Nil when `page` itself is
    /// taken: there is no room there at all.
    public static func room(at page: Int, besides taken: [ClosedRange<Int>], pages: Int?) -> ClosedRange<Int>? {
        let bounds = Self.bounds(pages)
        guard bounds.contains(page), !taken.contains(where: { $0.contains(page) }) else { return nil }
        let lo = taken.filter { $0.upperBound < page }.map { $0.upperBound + 1 }.max() ?? bounds.lowerBound
        let hi = taken.filter { $0.lowerBound > page }.map { $0.lowerBound - 1 }.min() ?? bounds.upperBound
        return max(lo, bounds.lowerBound)...min(hi, bounds.upperBound)
    }

    /// Where this range may go: the free run around its set end. Other classes' pages are walls a range stops at
    /// rather than crosses, so the walls are the room's ends. Without either end, or with one already on a taken page
    /// (a range saved before the rule), the file's bounds.
    func room(besides taken: [ClosedRange<Int>], pages: Int?) -> ClosedRange<Int> {
        guard let anchor = first ?? last, let room = Self.room(at: anchor, besides: taken, pages: pages) else { return Self.bounds(pages) }
        return room
    }

    /// `end` moved to `page` (nil empties it), kept within 1…`pages` and clear of the pages in `taken`; the other end
    /// is pushed along past it. The other end is also brought into the file, for a count learned after it was set.
    public func moving(_ end: End, to page: Int?, pages: Int?, besides taken: [ClosedRange<Int>] = []) -> PageRange {
        var bounds = room(besides: taken, pages: pages)

        // An empty range has no room yet: the page it is given decides it, and a taken page sets nothing.
        if first == nil, last == nil, let page {
            let file = Self.bounds(pages)
            guard let around = Self.room(at: min(max(page, file.lowerBound), file.upperBound), besides: taken, pages: pages) else { return self }
            bounds = around
        }

        let clamp = { (p: Int) in min(max(p, bounds.lowerBound), bounds.upperBound) }
        let moved = page.map(clamp)
        switch end {
        case .first: return PageRange(first: moved, last: last.map { max(clamp($0), moved ?? $0) })
        case .last: return PageRange(first: first.map { min(clamp($0), moved ?? $0) }, last: moved)
        }
    }

    /// A tap on `page` of the file's bar. A missing end is filled first, so a range set by taps never keeps one end
    /// empty for good; with both set, the nearer end comes to the page (the start on a tie, `moving` doing the push).
    /// A first tap on a page another class took sets nothing.
    public func tapping(_ page: Int, pages: Int?, besides taken: [ClosedRange<Int>] = []) -> PageRange {
        switch (first, last) {
        case (nil, nil):
            return moving(.first, to: page, pages: pages, besides: taken).moving(.last, to: page, pages: pages, besides: taken)
        case let (f?, nil): return page >= f ? moving(.last, to: page, pages: pages, besides: taken) : PageRange(first: page, last: f).clamped(to: room(besides: taken, pages: pages))
        case let (nil, l?): return page <= l ? moving(.first, to: page, pages: pages, besides: taken) : PageRange(first: l, last: page).clamped(to: room(besides: taken, pages: pages))
        case let (f?, l?): return moving(abs(page - f) <= abs(page - l) ? .first : .last, to: page, pages: pages, besides: taken)
        }
    }

    /// This range clear of `taken`: its start moved past any range it falls in, its end stopped before the next one.
    /// Empty when nothing is left, as for a class that only went back over pages taught before.
    public func fitted(besides taken: [ClosedRange<Int>], pages: Int?) -> PageRange {
        guard var start = first ?? last else { return self }
        while let wall = taken.first(where: { $0.contains(start) }) { start = wall.upperBound + 1 }
        guard let room = Self.room(at: start, besides: taken, pages: pages) else { return PageRange() }
        guard let end = last else { return PageRange(first: start) }
        guard end >= start else { return PageRange() }
        return PageRange(first: first == nil ? nil : start, last: min(end, room.upperBound))
    }

    private func clamped(to bounds: ClosedRange<Int>) -> PageRange {
        let clamp = { (p: Int) in min(max(p, bounds.lowerBound), bounds.upperBound) }
        return PageRange(first: first.map(clamp), last: last.map(clamp))
    }

    /// The whole range moved `pages` later (earlier when negative), its length kept and stopped at the file's ends and
    /// at other classes' pages. A range missing an end has no length to keep and stays where it is.
    public func shifted(by delta: Int, pages: Int?, besides taken: [ClosedRange<Int>] = []) -> PageRange {
        guard let f = first, let l = last else { return self }
        let bounds = room(besides: taken, pages: pages)
        let length = min(l - f, bounds.upperBound - bounds.lowerBound)
        let start = min(max(f + delta, bounds.lowerBound), bounds.upperBound - length)
        return PageRange(first: start, last: start + length)
    }

    /// `end` rests against a bound of the file, against another class's pages, or against the other end: where a drag
    /// stops giving, and a firmer tick tells so.
    public func touches(_ end: End, pages: Int?, besides taken: [ClosedRange<Int>] = []) -> Bool {
        guard let page = self[end] else { return false }
        let bounds = room(besides: taken, pages: pages)
        let other = end == .first ? last : first
        let wall = taken.contains { $0.lowerBound == page + 1 || $0.upperBound == page - 1 }
        return page == bounds.lowerBound || ((pages != nil || wall) && page == bounds.upperBound) || page == other
    }
}

extension SessionMaterial {
    public var pageRange: PageRange {
        get { PageRange(first: firstPage, last: lastPage) }
        set {
            firstPage = newValue.first
            lastPage = newValue.last
        }
    }

    /// One bound alone is that one page: a class that only says where it stopped still covered that page.
    public var pages: ClosedRange<Int>? {
        guard let a = firstPage ?? lastPage, let b = lastPage ?? firstPage else { return nil }
        return min(a, b)...max(a, b)
    }
}

extension CourseFile {
    /// Classes that name pages of `material`, in class order. A cancelled class taught nothing, whatever it links.
    func coverage(of material: UUID) -> [(session: Session, pages: ClosedRange<Int>)] {
        sessionLinks(of: material).compactMap { s, link in
            guard !s.isCancelled, let pages = link.pages else { return nil }
            return (s, pages)
        }
    }

    /// The file split where the classes covering it change, through `pageCount` (without it, the last page any class
    /// reached). Pages past the count are dropped: a range typed too long shouldn't make the file look longer.
    public func lectureProgress(of material: UUID, pageCount: Int?) -> [LectureSpan] {
        let covered = coverage(of: material)
        let end = pageCount ?? covered.map(\.pages.upperBound).max() ?? 0
        guard end > 0 else { return [] }

        var spans: [LectureSpan] = []
        for page in 1...end {
            let sessions = covered.filter { $0.pages.contains(page) }.map(\.session.id)
            if let last = spans.last, last.sessions == sessions {
                spans[spans.count - 1].lastPage = page
            } else {
                spans.append(LectureSpan(firstPage: page, lastPage: page, sessions: sessions))
            }
        }
        return spans
    }

    /// Each class's pages of `material` in page order, as `lectureProgress` cuts them at the count: the sections of
    /// the file's page strip. Classes never share a page (`progressOverlaps`), so one range per class is the whole of it.
    public func progressSections(of material: UUID, pageCount: Int?) -> [(session: UUID, pages: ClosedRange<Int>)] {
        var ranges: [(session: UUID, pages: ClosedRange<Int>)] = []
        for span in lectureProgress(of: material, pageCount: pageCount) {
            for session in span.sessions {
                if let i = ranges.firstIndex(where: { $0.session == session }) {
                    ranges[i].pages = ranges[i].pages.lowerBound...span.lastPage
                } else {
                    ranges.append((session, span.firstPage...span.lastPage))
                }
            }
        }
        return ranges
    }

    /// Two classes naming the same pages of one lecture file, each pair once with the later class second. A page is
    /// taught once: the second time is a recap, and counting it twice would make the progress read further back than
    /// the class went. Cancelled classes taught nothing and never overlap.
    public func progressOverlaps() -> [(material: UUID, earlier: (session: Session, pages: ClosedRange<Int>), later: (session: Session, pages: ClosedRange<Int>))] {
        var out: [(material: UUID, earlier: (session: Session, pages: ClosedRange<Int>), later: (session: Session, pages: ClosedRange<Int>))] = []
        for material in materials where material.role == .lecture {
            let covered = coverage(of: material.id).sorted { Session.inOrder($0.session, $1.session) }
            for (i, a) in covered.enumerated() {
                for b in covered[(i + 1)...] where a.pages.overlaps(b.pages) {
                    out.append((material.id, a, b))
                }
            }
        }
        return out
    }

    /// Pages of `material` the classes other than `session` took, in page order: where a range of `session` may not go.
    public func pagesTaken(in material: UUID, besides session: UUID) -> [ClosedRange<Int>] {
        pagesTaught(in: material, besides: session).map(\.pages).sorted { $0.lowerBound < $1.lowerBound }
    }

    /// The classes a new range of `material`'s pages can be saved as, the latest first: those held up to today that
    /// have no pages of it yet. A class with pages there is changed from its own section of the page strip instead,
    /// and a cancelled class taught nothing.
    public func sessionsForNewRange(of material: UUID, now: Date, settings: Settings, calendar: Calendar) -> [Session] {
        Session.held(among: sessions.filter { !$0.isCancelled }, now: now, settings: settings, calendar: calendar)
            .reversed()
            .filter { s in s.materials.first { $0.materialId == material }?.pages == nil }
    }
}

extension CourseFile {
    /// The pages each other class took through `material`, in class order: what a page bar lays under the class being
    /// edited.
    public func pagesTaught(in material: UUID, besides session: UUID) -> [(session: Session, pages: ClosedRange<Int>)] {
        coverage(of: material).filter { $0.session.id != session }
    }

    /// Classes linked to the file without pages: they used it, but nothing says which part.
    public func unrangedSessions(of material: UUID) -> [Session] {
        sessionLinks(of: material).filter { !$0.session.isCancelled && $0.link.pages == nil }.map(\.session)
    }

    /// The page after where the most recent class before `session` stopped in `material`. Nil when no earlier class
    /// names pages of it. The most recent, not the furthest: a lecturer who went back over a part picks up from there.
    public func resumePage(of material: UUID, for session: Session) -> Int? {
        coverage(of: material).last { $0.session.id != session.id && Session.inOrder($0.session, session) }.map { $0.pages.upperBound + 1 }
    }

    /// What the end-of-class prompt shows first for `session`: each lecture file it went through, from the page after
    /// the last class's to the furthest page `viewed` while recording. Pages already saved for the session stay as
    /// they are. Files: those linked to the session, then those viewed; with neither, the file the last class
    /// stopped in (the next lecture file once `pageCounts` says that one is done).
    public func suggestedProgress(for session: Session, viewed: [SessionMaterial], pageCounts: [UUID: Int] = [:]) -> [SessionMaterial] {
        var files = session.materials.map(\.materialId)
        for range in viewed where !files.contains(range.materialId) { files.append(range.materialId) }
        if files.isEmpty, let next = continuingFile(before: session, pageCounts: pageCounts) { files = [next] }
        return files.map { id in
            suggestedRange(of: id, for: session, seen: viewed.first { $0.materialId == id }, pageCount: pageCounts[id])
        }
    }

    /// The pages a new link of `material` to `session` starts with, by the prompt's rule. Without pages when nothing
    /// says where the class was (no earlier class reached the file, no recording saw it): a link without pages is the
    /// whole file, where a start alone would be one page.
    public func suggestedLink(of material: UUID, for session: Session, pageCount: Int?) -> SessionMaterial {
        let seen = viewedPages(of: session).first { $0.materialId == material }
        guard seen != nil || resumePage(of: material, for: session) != nil else { return SessionMaterial(materialId: material) }
        return suggestedRange(of: material, for: session, seen: seen, pageCount: pageCount)
    }

    /// What the session's recordings saw, one range per file across all of them. Only the recordings keep these
    /// until the prompt is saved, so a prompt opened again later starts from them. `stopped` is a recording that has
    /// just ended and isn't saved to the course yet: the prompt it raises has to see the same pages a reopened one will.
    public func viewedPages(of session: Session, including stopped: Recording? = nil) -> [SessionMaterial] {
        var ranges: [SessionMaterial] = []
        let saved = recordings.filter { $0.sessionId == session.id && $0.id != stopped?.id }
        for recording in saved + [stopped].compactMap({ $0 }) {
            for seen in recording.viewedPages() {
                guard let pages = seen.pages else { continue }
                if let i = ranges.firstIndex(where: { $0.materialId == seen.materialId }), let had = ranges[i].pages {
                    ranges[i].firstPage = min(had.lowerBound, pages.lowerBound)
                    ranges[i].lastPage = max(had.upperBound, pages.upperBound)
                } else {
                    ranges.append(SessionMaterial(materialId: seen.materialId, firstPage: pages.lowerBound, lastPage: pages.upperBound))
                }
            }
        }
        return ranges
    }

    /// The prompt's rule for one file: pages saved for the session stay; otherwise from the page after the last
    /// class's to the furthest page `seen` while recording.
    public func suggestedRange(of id: UUID, for session: Session, seen: SessionMaterial?, pageCount: Int?) -> SessionMaterial {
        let saved = session.materials.first { $0.materialId == id }
        var last = saved?.lastPage ?? seen?.lastPage
        var first = saved?.firstPage ?? resumePage(of: id, for: session) ?? 1
        if let count = pageCount {
            first = min(first, count)
            last = last.map { min($0, count) }
        }

        var range = PageRange(first: first, last: last)
        // Saved pages already passed the rule. Anything guessed is kept off other classes' pages: a class that only
        // went back over pages taught before (a recap) is suggested no pages rather than those.
        if saved?.firstPage == nil || saved?.lastPage == nil {
            range = range.fitted(besides: pagesTaken(in: id, besides: session.id), pages: pageCount)
        }
        return SessionMaterial(materialId: id, firstPage: range.first, lastPage: range.last)
    }

    /// The file the most recent ranged class before `session` stopped in. Once its count says the class reached the
    /// end, the lecture file after it by name (`05_`, then `06_`), the order `Lectures` is named in.
    func continuingFile(before session: Session, pageCounts: [UUID: Int]) -> UUID? {
        let earlier = sessions.filter { !$0.isCancelled && $0.id != session.id && Session.inOrder($0, session) }.sorted(by: Session.inOrder)
        guard let link = earlier.lazy.reversed().compactMap({ $0.materials.last { $0.pages != nil } }).first,
              let end = link.pages?.upperBound else { return nil }
        guard let count = pageCounts[link.materialId], end >= count else { return link.materialId }

        let lectures = lectureFiles
        guard let i = lectures.firstIndex(where: { $0.id == link.materialId }), i + 1 < lectures.count else { return nil }
        return lectures[i + 1].id
    }

    /// The course's lecture files in the order `Lectures` names them (`05_`, `05-1_`, `06_`): what a class goes
    /// through, and what the end-of-class prompt offers to add.
    public var lectureFiles: [Material] {
        materials.filter { $0.role == .lecture && !$0.isFolder && $0.status == .classified }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}

extension Recording {
    /// The lecture page on screen `time` seconds into the audio, as it was then, however briefly. Nil before the
    /// first page or while no file was open.
    public func visit(at time: TimeInterval) -> PageVisit? {
        guard let last = pages.last(where: { $0.at <= time }), last.page != nil else { return nil }
        return last
    }
}

extension Session {
    /// `16–18쪽`, or `16쪽` for one page: how a class's pages of a file are written wherever they are shown.
    public static func pagesLabel(_ pages: ClosedRange<Int>) -> String {
        pages.count == 1 ? String(localized: .sessionPage(pages.lowerBound)) : String(localized: .sessionPages(pages.lowerBound, pages.upperBound))
    }
}
