import Foundation

extension SessionMaterial {
    public var pageRange: PageRange {
        get { PageRange(first: firstPage, last: lastPage) }
        set {
            firstPage = newValue.first
            lastPage = newValue.last
        }
    }

    public var pages: ClosedRange<Int>? {
        guard let a = firstPage ?? lastPage, let b = lastPage ?? firstPage else { return nil }
        return min(a, b)...max(a, b)
    }
}

extension CourseFile {
    func coverage(of material: UUID) -> [(session: Session, pages: ClosedRange<Int>)] {
        sessionLinks(of: material).compactMap { s, link in
            guard !s.isCancelled, let pages = link.pages else { return nil }
            return (s, pages)
        }
    }

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

    // 한 쪽은 한 번 가르친다. 두 번째는 복습이고, 두 번 세면 진도가 실제 수업보다 뒤로 읽힌다.
    public func progressOverlaps() -> [(
        material: UUID, earlier: (session: Session, pages: ClosedRange<Int>), later: (session: Session, pages: ClosedRange<Int>)
    )] {
        var out:
            [(material: UUID, earlier: (session: Session, pages: ClosedRange<Int>), later: (session: Session, pages: ClosedRange<Int>))] =
                []
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

    public func pagesTaken(in material: UUID, besides session: UUID) -> [ClosedRange<Int>] {
        pagesTaught(in: material, besides: session).map(\.pages).sorted { $0.lowerBound < $1.lowerBound }
    }

    public func sessionsForNewRange(of material: UUID, now: Date, settings: Settings, calendar: Calendar) -> [Session] {
        Session.held(among: sessions.filter { !$0.isCancelled }, now: now, settings: settings, calendar: calendar)
            .reversed()
            .filter { s in s.materials.first { $0.materialId == material }?.pages == nil }
    }
}

extension CourseFile {
    public func pagesTaught(in material: UUID, besides session: UUID) -> [(session: Session, pages: ClosedRange<Int>)] {
        coverage(of: material).filter { $0.session.id != session }
    }

    public func unrangedSessions(of material: UUID) -> [Session] {
        sessionLinks(of: material).filter { !$0.session.isCancelled && $0.link.pages == nil }.map(\.session)
    }

    // 가장 멀리 간 수업이 아니라 가장 최근 수업을 따른다. 강의자가 한 부분을 다시 다뤘으면 거기서 이어 가기 때문이다.
    public func resumePage(of material: UUID, for session: Session) -> Int? {
        coverage(of: material).last { $0.session.id != session.id && Session.inOrder($0.session, session) }.map { $0.pages.upperBound + 1 }
    }

    public func suggestedProgress(for session: Session, viewed: [SessionMaterial], pageCounts: [UUID: Int] = [:]) -> [SessionMaterial] {
        var files = session.materials.map(\.materialId)
        for range in viewed where !files.contains(range.materialId) { files.append(range.materialId) }
        if files.isEmpty, let next = continuingFile(before: session, pageCounts: pageCounts) { files = [next] }
        return files.map { id in
            suggestedRange(of: id, for: session, seen: viewed.first { $0.materialId == id }, pageCount: pageCounts[id])
        }
    }

    // 쪽이 없는 연결은 파일 전체를 뜻하고 시작 쪽만 있으면 한 쪽을 뜻한다. 그래서 수업 위치를 알 수 없으면 쪽 없이
    // 연결한다.
    public func suggestedLink(of material: UUID, for session: Session, pageCount: Int?) -> SessionMaterial {
        let seen = viewedPages(of: session).first { $0.materialId == material }
        guard seen != nil || resumePage(of: material, for: session) != nil else { return SessionMaterial(materialId: material) }
        return suggestedRange(of: material, for: session, seen: seen, pageCount: pageCount)
    }

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

    public func suggestedRange(of id: UUID, for session: Session, seen: SessionMaterial?, pageCount: Int?) -> SessionMaterial {
        let saved = session.materials.first { $0.materialId == id }
        var last = saved?.lastPage ?? seen?.lastPage
        var first = saved?.firstPage ?? resumePage(of: id, for: session) ?? 1
        if let count = pageCount {
            first = min(first, count)
            last = last.map { min($0, count) }
        }

        var range = PageRange(first: first, last: last)
        if saved?.firstPage == nil || saved?.lastPage == nil {
            range = range.fitted(besides: pagesTaken(in: id, besides: session.id), pages: pageCount)
        }
        return SessionMaterial(materialId: id, firstPage: range.first, lastPage: range.last)
    }

    func continuingFile(before session: Session, pageCounts: [UUID: Int]) -> UUID? {
        let earlier = sessions.filter { !$0.isCancelled && $0.id != session.id && Session.inOrder($0, session) }.sorted(by: Session.inOrder)
        guard let link = earlier.lazy.reversed().compactMap({ $0.materials.last { $0.pages != nil } }).first,
            let end = link.pages?.upperBound
        else { return nil }
        guard let count = pageCounts[link.materialId], end >= count else { return link.materialId }

        let lectures = lectureFiles
        guard let i = lectures.firstIndex(where: { $0.id == link.materialId }), i + 1 < lectures.count else { return nil }
        return lectures[i + 1].id
    }

    public var lectureFiles: [Material] {
        materials.filter { $0.role == .lecture && !$0.isFolder && $0.status == .classified }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}

extension Recording {
    public func visit(at time: TimeInterval) -> PageVisit? {
        guard let last = pages.last(where: { $0.at <= time }), last.page != nil else { return nil }
        return last
    }
}

extension Session {
    public static func pagesLabel(_ pages: ClosedRange<Int>) -> String {
        pages.count == 1
            ? String(localized: .sessionPage(pages.lowerBound)) : String(localized: .sessionPages(pages.lowerBound, pages.upperBound))
    }
}
