import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing
@testable import Folio

/// Two classes of graph theory a week apart, with the matchings slides tracked.
@MainActor
struct LectureProgressModelTests {
    let workspace: Workspace
    let earlier: UUID
    let session: UUID
    let slides: FolioDomain.Material

    init() throws {
        workspace = try fixtureWorkspace()
        workspace.run(MaterialTrack(course: graphTheory))
        earlier = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now.addingTimeInterval(-7 * 86_400)))?.made)
        session = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now))?.made)
        slides = try #require(workspace.course(graphTheory)?.file.materials.first { $0.path == "Lectures/05_Matchings.pdf" })
    }

    var file: CourseFile { workspace.course(graphTheory)!.file }
    func links(_ id: UUID) -> [SessionMaterial] { file.sessions.first { $0.id == id }?.materials ?? [] }

    // MARK: The end-of-class prompt

    @Test func stoppingARecordingAsksFromTheLastClassToTheLastPageSeen() throws {
        workspace.run(MaterialLinkSession(course: graphTheory, material: slides.id, session: earlier, firstPage: 1, lastPage: 6))
        let recording = Recording(device: workspace.device, at: .now, sessionId: session, file: "Recordings/a.m4a", duration: 600,
                                  pages: [PageVisit(at: 0, materialId: slides.id, page: 6), PageVisit(at: 100, materialId: slides.id, page: 11)])
        workspace.askWrapUp(after: recording, course: graphTheory)
        let ask = try #require(workspace.wrapUpAsk)
        #expect(ask.session == session && ask.viewed == [SessionMaterial(materialId: slides.id, firstPage: 6, lastPage: 11)])

        let model = ClassWrapUpModel(workspace: workspace, course: graphTheory, session: session, viewed: ask.viewed)
        #expect(model.rows == [.init(id: slides.id, first: 7, last: 11)])
        #expect(model.seen(slides.id) == 6...11)
        #expect(model.refusal == nil && model.note == nil)
        model.wrapUp()
        #expect(links(session) == [SessionMaterial(materialId: slides.id, firstPage: 7, lastPage: 11)])
    }

    /// A recording without a class has nothing to wrap up. A course without lecture files still has units and a
    /// note to ask about; a class wrapped up with nothing missing isn't asked again.
    @Test func aRecordingAsksUnlessItsClassHasNothingLeft() throws {
        workspace.askWrapUp(after: Recording(device: workspace.device, at: .now, sessionId: nil, file: "Recordings/a.m4a"), course: graphTheory)
        #expect(workspace.wrapUpAsk == nil)
        // Linear algebra's files aren't tracked in the fixture, so it has no lecture files yet.
        let linearAlgebra = UUID(uuidString: "C0000000-0000-4000-8000-000000000001")!
        let other = try #require(workspace.run(SessionAdd(course: linearAlgebra, date: .now.addingTimeInterval(-200 * 86_400)))?.made)
        let recording = Recording(device: workspace.device, at: .now, sessionId: other, file: "Recordings/a.m4a")
        workspace.askWrapUp(after: recording, course: linearAlgebra)
        #expect(workspace.wrapUpAsk?.session == other)
        workspace.wrapUpAsk = nil

        let unit = try #require(workspace.run(UnitAdd(course: linearAlgebra, title: "행렬식"))?.made)
        workspace.run(SessionWrapUp(course: linearAlgebra, session: other, ranges: [], units: [unit], attendance: .present))
        _ = workspace.note(.rough, of: other, in: linearAlgebra)
        workspace.askWrapUp(after: recording, course: linearAlgebra)
        #expect(workspace.wrapUpAsk == nil)
    }

    @Test func aKeptFileNeedsBothPagesAndOnlyKeptFilesAreSaved() throws {
        let model = ClassWrapUpModel(workspace: workspace, course: graphTheory, session: session)
        #expect(model.rows.isEmpty)
        // The rest of the wrap-up can be saved without any progress.
        #expect(model.refusal == nil)
        #expect(model.addable.map(\.id) == [slides.id])
        model.add(slides.id)
        #expect(model.rows == [.init(id: slides.id, first: 1, last: nil)])
        #expect(model.refusal == String(localized: .sessionsProgressMissingLast("05_Matchings.pdf")))
        model.setRange(slides.id, PageRange(first: 1, last: 4))
        #expect(model.refusal == nil)
        model.toggle(slides.id)
        #expect(model.refusal == nil)
        model.toggle(slides.id)
        model.setRange(slides.id, PageRange(first: 2, last: 4))
        model.wrapUp()
        #expect(links(session) == [SessionMaterial(materialId: slides.id, firstPage: 2, lastPage: 4)])
    }

    /// The prompt is the one writer of a class's progress: dismissed unsaved, the class stays without pages, and
    /// opening it again from the class's menu fills the same pages from the recording, not the recording's first.
    @Test func aPromptDismissedAndOpenedAgainStartsAfterTheLastClass() throws {
        workspace.run(MaterialLinkSession(course: graphTheory, material: slides.id, session: earlier, firstPage: 1, lastPage: 6))
        let recording = Recording(device: workspace.device, at: .now, sessionId: session, file: "Recordings/a.m4a", duration: 600,
                                  pages: [PageVisit(at: 0, materialId: slides.id, page: 6), PageVisit(at: 100, materialId: slides.id, page: 11)])
        let ctx = ActionContext(gist: try #require(workspace.gist), device: workspace.device, now: workspace.now)
        try ctx.edit(graphTheory) { $0.recordings = [recording] }
        workspace.reload()
        #expect(links(session).isEmpty)

        let model = ClassWrapUpModel(workspace: workspace, course: graphTheory, session: session)
        #expect(model.rows == [.init(id: slides.id, first: 7, last: 11)])
        #expect(model.seen(slides.id) == 6...11)
    }

    @Test func aRangeFromTheFieldIsKeptAsIs() throws {
        let model = ClassWrapUpModel(workspace: workspace, course: graphTheory, session: session)
        model.add(slides.id)
        model.setRange(slides.id, PageRange(first: 9, last: 9))
        #expect(model.rows == [.init(id: slides.id, first: 9, last: 9)])
    }

    // MARK: The links popover

    @Test func aLectureLinkedToAClassStartsAfterTheLastOne() throws {
        let materials = MaterialsModel(workspace: workspace, course: try #require(workspace.course(graphTheory)))
        // No class has reached the file: linked without pages, the whole file.
        materials.link(slides.id, session: earlier, linked: true)
        #expect(links(earlier) == [SessionMaterial(materialId: slides.id)])
        materials.setPages(slides.id, session: earlier, PageRange(first: 1, last: 8))
        #expect(links(earlier) == [SessionMaterial(materialId: slides.id, firstPage: 1, lastPage: 8)])
        materials.link(slides.id, session: session, linked: true)
        #expect(links(session) == [SessionMaterial(materialId: slides.id, firstPage: 9)])
    }

    // MARK: A file's progress

    @Test func aFilesProgressNamesTheClasses() throws {
        workspace.run(MaterialLinkSession(course: graphTheory, material: slides.id, session: earlier, firstPage: 1, lastPage: 3))
        workspace.run(MaterialLinkSession(course: graphTheory, material: slides.id, session: session, firstPage: 4, lastPage: 5))
        let materials = MaterialsModel(workspace: workspace, course: try #require(workspace.course(graphTheory)))
        #expect(materials.isLecture(slides.id))

        let model = LectureProgressModel(workspace: workspace, course: graphTheory, material: slides.id)
        let days = [earlier, session].map { id in file.day(of: file.sessions.first { $0.id == id }!, calendar: workspace.calendar) }
        #expect(model.rows.map(\.pages) == ["p.1–3", "p.4–5"])
        #expect(model.rows.map { $0.classes.map(\.day) } == days.map { [$0] })
        // A class's day opens that class.
        #expect(model.rows.map { $0.classes.map(\.link) } == [[AppLink(.session, earlier)], [AppLink(.session, session)]])
        #expect(model.summary == String(localized: .materialsProgressCovered(5)))
        #expect(model.unranged == nil)
    }

    // MARK: Replay

    @Test func aLineShowsThePageWhereItTurns() throws {
        let store = workspace.course(graphTheory)!.store
        let recording = Recording(device: workspace.device, at: .now, sessionId: session, file: "Recordings/a.m4a", duration: 300,
                                  pages: [PageVisit(at: 0, materialId: slides.id, page: 4), PageVisit(at: 60, materialId: slides.id, page: 6)])
        try FileManager.default.createDirectory(at: store.recordingsURL, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: store.fileURL(recording.file))
        try store.saveTranscript(LectureTranscript(locale: "ko-KR", lines: [
            .init(start: 0, end: 20, text: "매칭"), .init(start: 20, end: 60, text: "증가 경로"), .init(start: 61, end: 80, text: "홀의 정리"),
        ]), of: recording)
        let ctx = ActionContext(gist: try #require(workspace.gist), device: workspace.device, now: workspace.now)
        try ctx.edit(graphTheory) { $0.recordings = [recording] }
        workspace.reload()
        let model = RecordingPlayerModel(workspace: workspace, courseId: graphTheory, store: store, recording: recording)
        #expect((0..<3).map { model.page(at: $0)?.page } == [4, nil, 6])
        #expect(model.pageLabel(try #require(model.page(at: 2))) == "p.6")
        #expect(model.pageLink(try #require(model.page(at: 2))) == AppLink(.material, slides.id, anchor: .page(6)))
        // A search leaves lines out, so each one left says its page.
        model.query = "경로"
        #expect(model.page(at: 1)?.page == 4)
    }
}
