import FolioActions
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

struct NoteActionTests {
    static let graphTheory = ActionTests.graphTheory
    static let note = UUID(uuidString: "6f1d2c4e-8a3b-4f5e-9c1d-2b7a8e0f3d41")!
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let gist: GISTStore

    init() throws {
        gist = GISTStore(url: try Fixture.standard.copyToTemp())
    }

    @discardableResult
    func run(_ action: some Action) throws -> ActionContext {
        let ctx = ActionContext(gist: gist, device: device, now: now)
        try action.run(ctx)
        return ctx
    }

    func file() throws -> CourseFile { try ActionContext(gist: gist, device: device).file(Self.graphTheory) }
    func store() throws -> CourseStore { try ActionContext(gist: gist, device: device).store(Self.graphTheory) }
    func text(_ path: String) throws -> String { try String(contentsOf: try store().fileURL(path), encoding: .utf8) }

    @Test func aTexNoteIsAFileWithAnEntry() throws {
        let id = UUID()
        try run(NoteAdd(id: id, course: Self.graphTheory, title: "매칭 정리", kind: .topic, format: .tex))
        let entry = try #require(try file().notes.first { $0.id == id })
        #expect(entry.path == "Notes/매칭 정리.tex" && entry.kind == .topic)
        let tex = try text(entry.path)
        #expect(tex.hasPrefix("\\documentclass") && tex.contains("\\section*{매칭 정리}") && !tex.contains("---"))
        #expect(try store().note(id: id)?.format == .tex)
    }

    @Test func aReviewNoteMadeForASessionIsItsUnfinishedReviewNote() throws {
        let session = UUID(), id = UUID()
        try run(SessionAdd(id: session, course: Self.graphTheory, date: now))
        try run(NoteAdd(id: id, course: Self.graphTheory, title: "복습", kind: .review, format: .tex, session: session, exam: UUID()))
        let s = try #require(try file().sessions.first { $0.id == session })
        #expect(s.reviewNoteId == id && s.reviewNoteUnfinished)
        let entry = try #require(try file().notes.first { $0.id == id })
        #expect(entry.sessionId == session && entry.examId == nil)
    }

    @Test func aSecondNoteOfTheSameTitleGetsANumber() throws {
        try run(NoteAdd(id: UUID(), course: Self.graphTheory, title: "2주차-1"))
        #expect(try file().notes.map(\.path).contains("Notes/2주차-1 2.md"))
    }

    @Test func linkingChangesTheEntryAndLeavesTheFile() throws {
        let before = try text("Notes/2주차-1.md")
        try run(NoteLink(course: Self.graphTheory, note: Self.note, kind: .topic))
        #expect(try file().notes.first { $0.id == Self.note }?.kind == .topic)
        #expect(try text("Notes/2주차-1.md") == before)
    }

    @Test func removingANoteDropsItsEntry() throws {
        try run(NoteRemove(course: Self.graphTheory, note: "Notes/2주차-1.md"))
        #expect(try file().notes.contains { $0.id == Self.note } == false)
    }

    @Test func aTexNotesPDFGoesToExports() throws {
        try run(NoteAdd(id: UUID(), course: Self.graphTheory, title: "증명", format: .tex))
        let folder = TexEngine.outputFolder(for: try store().fileURL("Notes/증명.tex"))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let built = folder.appending(path: "\(UUID().uuidString).pdf")
        try Data("%PDF".utf8).write(to: built)
        let elsewhere = FileManager.default.temporaryDirectory.appending(path: "folio-\(UUID().uuidString).pdf")
        try Data("%PDF".utf8).write(to: elsewhere)
        #expect(throws: ActionError.self) { try run(NoteBuild(course: Self.graphTheory, note: "Notes/증명.tex", pdf: elsewhere.path)) }
        let ctx = try run(NoteBuild(course: Self.graphTheory, note: "Notes/증명.tex", pdf: built.path))
        #expect(ctx.changes.first == Change(.added, "2026-3/EC4207 그래프 이론/Notes/Exports/증명.pdf"))
        #expect(try text("Notes/Exports/증명.pdf") == "%PDF")
        #expect(throws: ActionError.self) { try run(NoteBuild(course: Self.graphTheory, note: "Notes/2주차-1.md", pdf: built.path)) }
    }

    @Test func anExamSummarysPDFGoesToExercises() throws {
        try run(NoteAdd(id: UUID(), course: Self.graphTheory, title: "중간 정리", kind: .examSummary, format: .tex))
        let folder = TexEngine.outputFolder(for: try store().fileURL("Notes/중간 정리.tex"))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let built = folder.appending(path: "\(UUID().uuidString).pdf")
        try Data("%PDF".utf8).write(to: built)
        try run(NoteBuild(course: Self.graphTheory, note: "Notes/중간 정리.tex", pdf: built.path))
        #expect(try text("Exercises/중간 정리.pdf") == "%PDF")
    }

    /// Unknown keys stay in the file; references to things that are gone are dropped; an id another note already has
    /// (a copy made in Finder) is replaced; a second run finds nothing to do.
    @Test func migrationMovesFolioKeysOnly() throws {
        let gone = UUID()
        let notes = try store().url.appending(path: "Notes")
        try "---\nid: \(Self.note.uuidString)\nkind: review\nsessionId: \(gone.uuidString)\nauthor: 나\n---\n\n# 사본\n"
            .write(to: notes.appending(path: "사본.md"), atomically: true, encoding: .utf8)
        try run(NoteMigrate(course: Self.graphTheory))

        let entry = try #require(try file().notes.first { $0.path == "Notes/사본.md" })
        #expect(entry.id != Self.note && entry.kind == .review && entry.sessionId == nil)
        #expect(try text("Notes/사본.md") == "---\nauthor: 나\n---\n\n# 사본\n")

        let after = try file()
        try run(NoteMigrate(course: Self.graphTheory))
        #expect(try file().notes == after.notes)
    }
}
