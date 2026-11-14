import Foundation

public struct TranscriptionHints: Sendable, Equatable {
    public var title: String
    // 프롬프트가 끝에서부터 잘리므로 중요한 용어가 앞에 온다.
    public var terms: [String]

    public init(title: String, terms: [String]) {
        self.title = title
        self.terms = terms
    }

    // Whisper는 프롬프트를 바로 앞에 말한 글로 읽는다. 영어 강의에서는 한국어 틀 낱말을 언어를 바꾸라는 신호로 읽으므로
    // 한국어 틀 낱말을 넣지 않는다.
    public func prompt(terms count: Int? = nil) -> String {
        let shown = terms.prefix(count ?? terms.count)
        return shown.isEmpty ? "\(title)." : "\(title). \(shown.joined(separator: ", "))."
    }
}

extension CourseFile {
    public func transcriptionContext(for session: Session, recording: Recording? = nil) -> TranscriptionContext {
        let slides = lectureSlides(for: session, recording: recording)
        return TranscriptionContext(source: slides.source, slides: slides.pages, topics: transcriptionTopics(for: session))
    }

    func transcriptionTopics(for session: Session) -> [String] {
        unitsCovering(session: session.id).compactMap { id in units.first { $0.id == id }?.title }
    }

    public func lectureSlides(for session: Session, recording: Recording? = nil) -> (
        source: TranscriptionContext.Source?, pages: [LecturePages]
    ) {
        func pages(_ link: SessionMaterial) -> LecturePages? {
            materials.first { $0.id == link.materialId && $0.isPDF }.map {
                LecturePages(path: $0.path, first: link.firstPage, last: link.lastPage, materialId: $0.id)
            }
        }
        let viewed = (recording?.viewedPages() ?? []).compactMap(pages)
        if !viewed.isEmpty { return (.recording, viewed) }

        let linked = session.materials.compactMap(pages)
        let rest = materials(of: .session(session.id))
            .filter { item in item.material.isPDF && !linked.contains { $0.materialId == item.material.id } }
        let unitOnly = rest.filter { !$0.routes.contains(.direct) }
        let whole = rest.map(\.material).sorted { $0.path < $1.path }.map { LecturePages(path: $0.path, materialId: $0.id) }
        if !linked.isEmpty || !whole.isEmpty { return (unitOnly.isEmpty ? .session : .tagged, linked + whole) }

        let week =
            materials
            .filter {
                $0.isPDF && $0.path.hasPrefix(CourseFolder.lectures.rawValue + "/")
                    && StandardLayout.lectureWeek(($0.path as NSString).lastPathComponent) == session.week
            }
            .sorted { $0.path < $1.path }
            .map { LecturePages(path: $0.path, materialId: $0.id) }
        return (week.isEmpty ? nil : .week, week)
    }

    @discardableResult
    public mutating func linkViewedPages(of recording: Recording) -> Int {
        guard let session = recording.sessionId, let s = sessions.firstIndex(where: { $0.id == session }) else { return 0 }
        var linked = 0
        for range in recording.viewedPages() where !sessions[s].materials.contains(where: { $0.materialId == range.materialId }) {
            guard let material = materials.first(where: { $0.id == range.materialId }) else { continue }
            var pages = range.pageRange
            // 렉처의 한 쪽은 한 수업의 것이다(`Session.progressOverlap`). 다른 수업이 가진 쪽은 다시 훑어본 것이므로, 그 쪽만
            // 본 녹음은 아무것도 더하지 않는다.
            if material.role == .lecture {
                pages = pages.fitted(besides: pagesTaken(in: material.id, besides: session), pages: nil)
                guard pages.first != nil || pages.last != nil else { continue }
            }
            linkMaterial(range.materialId, session: session, firstPage: pages.first, lastPage: pages.last)
            linked += 1
        }
        return linked
    }
}
