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

extension SessionMaterial {
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
            let saved = session.materials.first { $0.materialId == id }
            let seen = viewed.first { $0.materialId == id }
            var last = saved?.lastPage ?? seen?.lastPage
            var first: Int
            if let given = saved?.firstPage {
                first = given
            } else {
                first = resumePage(of: id, for: session) ?? 1
                // The class only went back over pages covered before (a recap): those pages, not an empty range.
                if let end = last, first > end { first = min(seen?.firstPage ?? end, end) }
            }
            if let count = pageCounts[id] {
                first = min(first, count)
                last = last.map { min($0, count) }
            }
            return SessionMaterial(materialId: id, firstPage: first, lastPage: last)
        }
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
