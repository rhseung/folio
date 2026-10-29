import FolioActions
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

struct ActionTests {
    static let graphTheory = UUID(uuidString: "C0000000-0000-4000-8000-000000000002")!
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let gist: GISTStore

    init() throws {
        gist = GISTStore(url: try Fixture.standard.copyToTemp())
    }

    @discardableResult
    func run(_ action: some Action, dryRun: Bool = false) throws -> ActionContext {
        let ctx = ActionContext(gist: gist, device: device, now: now, dryRun: dryRun)
        try action.run(ctx)
        return ctx
    }

    func file() throws -> CourseFile { try ActionContext(gist: gist, device: device).file(Self.graphTheory) }

    @Test func aPathFieldNamesAFile() {
        let note = NoteRemove.spec.fields.first { $0.name == "note" }
        #expect(note?.ref == "NotePath")
        #expect(note?.type == "String")
    }

    /// The app enables its buttons with a dry run over the documents it shows, which may be ahead of the disk.
    @Test func aCheckReadsThePreloadedDocuments() throws {
        let disk = ActionContext(gist: gist, device: device)
        var doc = try disk.store(Self.graphTheory).load()
        let component = GradeComponent(device: device, at: now, name: "중간고사", weight: 30, order: 99, aggregation: .single)
        doc.model.components.append(component)
        doc.model.scores.append(ScoreEntry(device: device, at: now, componentId: component.id, title: "", score: 11, max: 20))
        let check = ActionContext(gist: gist, device: device, now: now, dryRun: true)
        check.preload(courses: [doc], transcript: try disk.transcript(), catalog: try disk.catalog(), settings: try disk.settings())
        #expect(throws: ActionError.self) { try ScoreAdd(course: Self.graphTheory, component: component.id, score: 12, max: 20).run(check) }
    }

    @Test func aDryRunReportsTheChangeAndWritesNothing() throws {
        let url = try ActionContext(gist: gist, device: device).store(Self.graphTheory).courseFileURL
        let before = try Data(contentsOf: url)
        let id = UUID()
        let ctx = try run(SessionAdd(id: id, course: Self.graphTheory, date: now), dryRun: true)
        #expect(try Data(contentsOf: url) == before)
        #expect(ctx.changes.contains { $0.kind == .added && $0.item == "sessions/\(id.uuidString)" })
        #expect(ctx.made == id)
    }

    @Test func aSessionANotePointsAtStays() throws {
        let kept = UUID(), free = UUID()
        try run(SessionAdd(id: kept, course: Self.graphTheory, date: now))
        try run(SessionAdd(id: free, course: Self.graphTheory, date: now.addingTimeInterval(86_400)))
        try run(SessionNote(course: Self.graphTheory, session: kept, kind: .review))

        #expect(try file().sessions.first { $0.id == kept }?.reviewNoteUnfinished == true)
        #expect(throws: ActionError.self) { try run(SessionRemove(course: Self.graphTheory, sessions: [kept, free])) }
        #expect(try file().sessions.count == 2)
        try run(SessionRemove(course: Self.graphTheory, sessions: [free]))
        #expect(try file().sessions.map(\.id) == [kept])
    }

    @Test func aNewExamGetsItsFolder() throws {
        let exam = ExamAdd(course: Self.graphTheory, title: "Quiz1", kind: .quiz, start: now)
        let ctx = try run(exam)
        let folder = try #require(ctx.changes.first { $0.path.hasSuffix("/") }).path
        #expect(FileManager.default.fileExists(atPath: gist.url.appending(path: folder).path))
        #expect(try file().exams.contains { $0.id == ctx.made })
    }

    @Test func aNoteChangedElsewhereIsNotOverwritten() throws {
        let store = try ActionContext(gist: gist, device: device).store(Self.graphTheory)
        let path = "Notes/2주차-1.md"
        let read = try String(contentsOf: store.fileURL(path), encoding: .utf8)
        try run(NoteWrite(course: Self.graphTheory, note: path, text: read + "\n바깥에서 고침", expected: read))
        #expect(throws: ActionError.conflict("노트가 다른 곳에서 바뀌었습니다: \(path)")) {
            try run(NoteWrite(course: Self.graphTheory, note: path, text: "덮어쓰기", expected: read))
        }
        #expect(try String(contentsOf: store.fileURL(path), encoding: .utf8).hasSuffix("바깥에서 고침"))
    }

    @Test func everyActionHasItsOwnCommand() {
        let commands = Actions.all.map { $0.command }
        #expect(Set(commands).count == commands.count)
    }
}
