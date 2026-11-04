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
        let linked = try file()
        #expect(linked.meta(of: entry).sessionId == session && entry.examId == nil)
    }

    /// A session holds one review note; another can't take it from the app, the CLI or MCP alike.
    @Test func aSessionsReviewNoteIsNotTaken() throws {
        let session = UUID(), first = UUID(), second = UUID()
        try run(SessionAdd(id: session, course: Self.graphTheory, date: now))
        try run(NoteAdd(id: first, course: Self.graphTheory, title: "복습", kind: .review, session: session))
        let name = try file().name(of: try #require(try file().sessions.first { $0.id == session }))
        #expect(throws: ActionError.rule("회차 \(name)에는 이미 복습 노트가 있습니다")) {
            try run(NoteAdd(id: second, course: Self.graphTheory, title: "복습 2", kind: .review, session: session))
        }
        try run(NoteAdd(id: second, course: Self.graphTheory, title: "복습 2"))
        #expect(throws: ActionError.self) { try run(NoteLink(course: Self.graphTheory, note: second, kind: .review, session: session)) }
        #expect(try file().sessions.first { $0.id == session }?.reviewNoteId == first)
    }

    /// The editor saves a math change through `note link`; it isn't writing the note, so it stays unfinished.
    @Test func relinkingAReviewNoteKeepsItUnfinished() throws {
        let session = UUID(), id = UUID()
        try run(SessionAdd(id: session, course: Self.graphTheory, date: now))
        try run(NoteAdd(id: id, course: Self.graphTheory, title: "복습", kind: .review, session: session))
        try run(NoteLink(course: Self.graphTheory, note: id, kind: .review, session: session, math: .asciimath))
        let s = try #require(try file().sessions.first { $0.id == session })
        #expect(s.reviewNoteId == id && s.reviewNoteUnfinished)
        #expect(try file().notes.first { $0.id == id }?.math == .asciimath)
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
        #expect(ctx.changes.first == Change(.added, "2026-3/EC4207 그래프 이론/Study/증명.pdf"))
        #expect(try text("Study/증명.pdf") == "%PDF")
        #expect(throws: ActionError.self) { try run(NoteBuild(course: Self.graphTheory, note: "Notes/2주차-1.md", pdf: built.path)) }
    }

    /// Exports are placed by title, so another tool's export can sit there already. Like `material build`, only this
    /// note's own PDF is replaced without asking, and a replaced one goes to the Trash.
    @Test func aNoteBuildReplacesOnlyItsOwnPDF() throws {
        try run(NoteAdd(id: UUID(), course: Self.graphTheory, title: "증명", format: .tex))
        let folder = TexEngine.outputFolder(for: try store().fileURL("Notes/증명.tex"))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func built(_ text: String) throws -> String {
            let url = folder.appending(path: "\(UUID().uuidString).pdf")
            try Data(text.utf8).write(to: url)
            return url.path
        }
        let exports = try store().fileURL("Study")
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        try Data("%PDF theirs".utf8).write(to: exports.appending(path: "증명.pdf"))

        #expect(throws: ActionError.conflict("같은 이름의 PDF가 이미 있고 Folio가 만든 것이 아니라서 바꾸지 않았습니다: Study/증명.pdf. 바꾸려면 --overwrite를 줍니다")) {
            try run(NoteBuild(course: Self.graphTheory, note: "Notes/증명.tex", pdf: try built("%PDF mine")))
        }
        #expect(try text("Study/증명.pdf") == "%PDF theirs")
        try run(NoteBuild(course: Self.graphTheory, note: "Notes/증명.tex", pdf: try built("%PDF mine"), overwrite: true))
        #expect(try text("Study/증명.pdf") == "%PDF mine")
        try run(NoteBuild(course: Self.graphTheory, note: "Notes/증명.tex", pdf: try built("%PDF again")))
        #expect(try text("Study/증명.pdf") == "%PDF again")
    }

    /// Without an entry there is nowhere to keep the hash, so the next build couldn't tell its own PDF.
    @Test func aNoteWithoutAnEntryIsNotBuilt() throws {
        try "\\documentclass{article}\n".write(to: try store().url.appending(path: "Notes/바깥.tex"), atomically: true, encoding: .utf8)
        #expect(throws: ActionError.rule("course.json에 항목이 없는 노트라서 빌드하지 않습니다: Notes/바깥.tex. 먼저 folio note adopt로 들입니다")) {
            try run(NoteBuild(course: Self.graphTheory, note: "Notes/바깥.tex"))
        }
    }

    @Test func anExamSummarysPDFGoesToStudy() throws {
        try run(NoteAdd(id: UUID(), course: Self.graphTheory, title: "중간 정리", kind: .examSummary, format: .tex))
        let folder = TexEngine.outputFolder(for: try store().fileURL("Notes/중간 정리.tex"))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let built = folder.appending(path: "\(UUID().uuidString).pdf")
        try Data("%PDF".utf8).write(to: built)
        try run(NoteBuild(course: Self.graphTheory, note: "Notes/중간 정리.tex", pdf: built.path))
        #expect(try text("Study/중간 정리.pdf") == "%PDF")
        #expect(try file().materials.contains { $0.path == "Study/중간 정리.pdf" })
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
        let migrated = try file()
        #expect(entry.id != Self.note && entry.kind == .review && migrated.meta(of: entry).sessionId == nil)
        #expect(try text("Notes/사본.md") == "---\nauthor: 나\n---\n\n# 사본\n")

        let after = try file()
        try run(NoteMigrate(course: Self.graphTheory))
        #expect(try file().notes == after.notes)
    }

    /// Before #206 a note that lost its session kept it in its frontmatter, so two notes may claim one session.
    @Test func migrationKeepsOneReviewNotePerSession() throws {
        let session = UUID()
        try run(SessionAdd(id: session, course: Self.graphTheory, date: now))
        let notes = try store().url.appending(path: "Notes")
        for name in ["정리", "정리 2"] {
            try "---\nid: \(UUID().uuidString)\nkind: review\nsessionId: \(session.uuidString)\n---\n\n# \(name)\n"
                .write(to: notes.appending(path: "\(name).md"), atomically: true, encoding: .utf8)
        }
        try run(NoteMigrate(course: Self.graphTheory))
        let claims = try file().notes.filter { $0.path.hasPrefix("Notes/정리") }
        // The session points at one of them, so it no longer asks for a review note.
        let pointed = try #require(try file().sessions.first { $0.id == session }?.reviewNoteId)
        #expect(claims.count == 2 && claims.contains { $0.id == pointed })
    }

    func meta(_ id: UUID) throws -> NoteMeta {
        let f = try file()
        return f.meta(of: try #require(f.notes.first { $0.id == id }))
    }

    /// A class note's units are its session's as they are now, so unlinking the class from a unit takes the note off it.
    @Test func aSessionNotesUnitsFollowTheSession() throws {
        let session = UUID(), unit = UUID(), note = UUID()
        try run(SessionAdd(id: session, course: Self.graphTheory, date: now))
        try run(UnitAdd(id: unit, course: Self.graphTheory, title: "매칭"))
        try run(UnitLink(course: Self.graphTheory, unit: unit, sessions: [session]))
        try run(SessionNote(id: note, course: Self.graphTheory, session: session, kind: .review))
        #expect(try file().notes.first { $0.id == note }?.unitIds == [])
        #expect(try meta(note).unitIds == [unit] && meta(note).sessionId == session)
        try run(UnitLink(course: Self.graphTheory, unit: unit, sessions: [session], linked: false))
        #expect(try meta(note).unitIds == [])
    }

    @Test func anExamSummarysUnitsFollowTheScope() throws {
        let exam = UUID(), unit = UUID(), note = UUID()
        try run(ExamAdd(id: exam, course: Self.graphTheory, title: "모의고사"))
        try run(UnitAdd(id: unit, course: Self.graphTheory, title: "매칭"))
        try run(ExamSummary(note: note, course: Self.graphTheory, exam: exam))
        #expect(try meta(note).unitIds == [])
        try run(ExamScope(course: Self.graphTheory, exam: exam, unit: unit))
        #expect(try meta(note).unitIds == [unit])
    }

    /// Becoming a topic note doesn't bring back units the note had as another kind, and leaving it drops them.
    @Test func changingKindDropsTheOtherKindsLinks() throws {
        let session = UUID(), unit = UUID(), other = UUID(), note = UUID()
        try run(SessionAdd(id: session, course: Self.graphTheory, date: now))
        try run(UnitAdd(id: unit, course: Self.graphTheory, title: "매칭"))
        try run(UnitAdd(id: other, course: Self.graphTheory, title: "트리"))
        try run(UnitLink(course: Self.graphTheory, unit: unit, sessions: [session]))
        try run(NoteAdd(id: note, course: Self.graphTheory, title: "필기", kind: .rough, session: session))
        try run(NoteLink(course: Self.graphTheory, note: note, kind: .topic, units: [other]))
        #expect(try meta(note).unitIds == [other] && meta(note).sessionId == nil)
        #expect(try file().sessions.first { $0.id == session }?.roughNoteId == nil)
        try run(NoteLink(course: Self.graphTheory, note: note, kind: .rough, session: session, units: [other]))
        #expect(try file().notes.first { $0.id == note }?.unitIds == [])
        #expect(try meta(note).unitIds == [unit])
    }

    /// The session holds the link alone, so it can't name a note of another kind.
    @Test func aSessionPointsOnlyAtANoteOfItsSlotsKind() throws {
        let session = UUID(), note = UUID()
        try run(SessionAdd(id: session, course: Self.graphTheory, date: now))
        try run(NoteAdd(id: note, course: Self.graphTheory, title: "메모"))
        let ctx = ActionContext(gist: gist, device: device, now: now)
        #expect(throws: ActionError.self) {
            try ctx.edit(Self.graphTheory) { f in
                if let i = f.sessions.firstIndex(where: { $0.id == session }) { f.sessions[i].reviewNoteId = note }
            }
        }
    }

    /// `import calendar` gives a free note named after a class's topic to that class as its review note.
    @Test func importCalendarMakesTheNoteAReviewNote() throws {
        let note = UUID()
        try run(NoteAdd(id: note, course: Self.graphTheory, title: "평면 그래프"))
        let start = ISO8601DateFormatter().date(from: "2026-10-26T01:00:00Z")!
        try run(ImportCalendar(meetings: [CalendarMeeting(course: "EC4207 그래프 이론", start: start, end: start + 4500, room: "A229", topic: "평면 그래프")]))
        let s = try #require(try file().sessions.first { $0.reviewNoteId == note })
        #expect(try meta(note).kind == .review && meta(note).sessionId == s.id)
    }
}
