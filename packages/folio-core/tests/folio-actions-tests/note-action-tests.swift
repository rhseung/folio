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

    /// The app re-reads its note and card lists from these, whichever screen or tool ran the action.
    @Test func changesSayWhetherNotesOrCardsWereTouched() throws {
        let id = UUID(), unit = UUID()
        let added = try run(NoteAdd(id: id, course: Self.graphTheory, title: "매칭 정리"))
        #expect(added.changes.filter(\.touchesNotes).count == 2 && !added.changes.contains(where: \.touchesQuizzes))
        let unitAdded = try run(UnitAdd(id: unit, course: Self.graphTheory, title: "매칭"))
        #expect(!unitAdded.changes.contains { $0.touchesNotes || $0.touchesQuizzes })
        let linked = try run(NoteLink(course: Self.graphTheory, note: id, kind: .unit, units: [unit]))
        #expect(linked.changes.map(\.touchesNotes) == [true])
        let card = QuizCard(device: device, at: now, unitId: unit, type: .free, category: .definition, prompt: "p", answer: "a")
        let saved = try run(QuizCardSave(course: Self.graphTheory, cards: [card]))
        #expect(saved.changes.map(\.touchesQuizzes) == [true] && !saved.changes.contains(where: \.touchesNotes))
        let answered = try run(QuizRecord(course: Self.graphTheory, attempt: QuizAttemptEvent(cardId: card.id, verdict: .wrong, grader: .self)))
        #expect(answered.changes.map(\.touchesQuizzes) == [true])
    }

    @Test func aTexNoteIsAFileWithAnEntry() throws {
        let id = UUID()
        try run(NoteAdd(id: id, course: Self.graphTheory, title: "매칭 정리", kind: .unit, format: .tex))
        let entry = try #require(try file().notes.first { $0.id == id })
        #expect(entry.path == "Notes/매칭 정리.tex" && entry.kind == .unit)
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
        let name = try file().title(of: try #require(try file().sessions.first { $0.id == session }), calendar: .current)
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

    /// Classes caught up on at once share one review note: linking adds a class without taking the note off the others.
    @Test func aReviewNoteGathersSeveralSessions() throws {
        let days = [0.0, 2, 7].map { now.addingTimeInterval($0 * 86_400) }
        let ids = days.map { _ in UUID() }
        for (id, day) in zip(ids, days) { try run(SessionAdd(id: id, course: Self.graphTheory, date: day)) }
        let note = UUID()
        try run(NoteAdd(id: note, course: Self.graphTheory, title: "rdt 정리", kind: .review, session: ids[0]))
        try run(NoteLinkSessions(course: Self.graphTheory, note: note, sessions: [ids[2], ids[1]]))
        #expect(try file().sessions(pointingAt: note).map(\.id) == ids)

        // The note was made from the template, so every class it covers waits for it to be written; writing it
        // finishes them together.
        #expect(try file().sessions.filter { ids.contains($0.id) }.allSatisfy(\.reviewNoteUnfinished))
        try run(SessionSet(course: Self.graphTheory, session: ids[1], reviewUnfinished: .set(false)))
        #expect(try !file().sessions.contains { ids.contains($0.id) && $0.reviewNoteUnfinished })

        // `note link` adds too, and doesn't move it.
        try run(NoteUnlinkSession(course: Self.graphTheory, note: note, session: ids[0]))
        #expect(try file().sessions(pointingAt: note).map(\.id) == [ids[1], ids[2]])

        // A session the note isn't on is a mistake to report, not a silent success.
        #expect(throws: ActionError.self) { try run(NoteUnlinkSession(course: Self.graphTheory, note: note, session: ids[0])) }
        try run(NoteLink(course: Self.graphTheory, note: note, kind: .review, session: ids[0]))
        #expect(try meta(note).sessionIds == ids)
        try run(NoteRemove(course: Self.graphTheory, note: "Notes/rdt 정리.md"))
        #expect(try file().sessions.allSatisfy { $0.reviewNoteId != note })
    }

    /// The whole list is checked before anything is written, so one refused class leaves the others unlinked.
    @Test func linkingSessionsRefusesBeforeWriting() throws {
        let free = UUID(), taken = UUID(), note = UUID(), other = UUID()
        try run(SessionAdd(id: free, course: Self.graphTheory, date: now))
        try run(SessionAdd(id: taken, course: Self.graphTheory, date: now.addingTimeInterval(86_400)))
        try run(NoteAdd(id: other, course: Self.graphTheory, title: "다른 정리", kind: .review, session: taken))
        try run(NoteAdd(id: note, course: Self.graphTheory, title: "정리", kind: .review))
        #expect(throws: ActionError.self) { try run(NoteLinkSessions(course: Self.graphTheory, note: note, sessions: [free, taken])) }
        #expect(try file().sessions(pointingAt: note).isEmpty)

        // Only a review note covers several classes; a rough note is linked with `note link`.
        #expect(throws: ActionError.self) { try run(NoteLinkSessions(course: Self.graphTheory, note: Self.note, sessions: [free])) }
    }

    @Test func aSecondNoteOfTheSameTitleGetsANumber() throws {
        try run(NoteAdd(id: UUID(), course: Self.graphTheory, title: "09-08(화) 매칭"))
        #expect(try file().notes.map(\.path).contains("Notes/09-08(화) 매칭 2.md"))
    }

    @Test func linkingChangesTheEntryAndLeavesTheFile() throws {
        let before = try text("Notes/09-08(화) 매칭.md")
        try run(NoteLink(course: Self.graphTheory, note: Self.note, kind: .unit))
        #expect(try file().notes.first { $0.id == Self.note }?.kind == .unit)
        #expect(try text("Notes/09-08(화) 매칭.md") == before)
    }

    @Test func removingANoteDropsItsEntry() throws {
        try run(NoteRemove(course: Self.graphTheory, note: "Notes/09-08(화) 매칭.md"))
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
        #expect(throws: ActionError.self) { try run(NoteBuild(course: Self.graphTheory, note: "Notes/09-08(화) 매칭.md", pdf: built.path)) }
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

    /// A note with frontmatter that already has an entry (adopted, or linked in the app).
    func entryWithFrontmatter(_ frontmatter: String, body: String, tags: [String] = [], exam: UUID? = nil) throws -> UUID {
        let id = UUID()
        try run(NoteAdd(id: id, course: Self.graphTheory, title: "기출", kind: .examSummary, exam: exam))
        try ActionContext(gist: gist, device: device, now: now).edit(Self.graphTheory) { f in
            f.notes[try #require(f.notes.firstIndex { $0.id == id })].tags = tags
        }
        try "---\n\(frontmatter)---\n\(body)".write(to: try store().fileURL("Notes/기출.md"), atomically: true, encoding: .utf8)
        return id
    }

    func entry(_ id: UUID) throws -> NoteEntry { try #require(try file().notes.first { $0.id == id }) }

    /// The real case: an entry with no tags and two in the frontmatter. A dry run shows the merge and writes nothing.
    @Test func migrationMergesTagsIntoAnExistingEntry() throws {
        let id = try entryWithFrontmatter("tags:\n  - math/graph-theory\n  - type/exam\ndate: 2026-09-21\n", body: "\n# 기출\n")
        let preview = ActionContext(gist: gist, device: device, now: now, dryRun: true)
        try NoteMigrate(course: Self.graphTheory).run(preview)
        let field = preview.changes.compactMap { $0.fields?.first { $0.name == "tags" } }.first
        let tags = try #require(field)
        #expect(tags.before == .array([]) && tags.after == .array([.string("math/graph-theory"), .string("type/exam")]))
        #expect(try entry(id).tags == [] && text("Notes/기출.md").hasPrefix("---\ntags:"))

        try run(NoteMigrate(course: Self.graphTheory))
        #expect(try entry(id).tags == ["math/graph-theory", "type/exam"])
        #expect(try text("Notes/기출.md") == "---\ndate: 2026-09-21\n---\n\n# 기출\n")
        let after = try file()
        try run(NoteMigrate(course: Self.graphTheory))
        #expect(try file().notes == after.notes)
    }

    /// The entry wins where it holds a value: tags are joined in its order, and its kind, exam and math stay.
    @Test func migrationKeepsTheEntrysValues() throws {
        let exam = UUID(), other = UUID()
        try run(ExamAdd(id: exam, course: Self.graphTheory, title: "모의고사"))
        try run(ExamAdd(id: other, course: Self.graphTheory, title: "기말"))
        let id = try entryWithFrontmatter("kind: review\nexamId: \(other)\ntags: [type/exam, math/graph]\nmath: latex\n",
                                          body: "\n# 기출\n", tags: ["mine", "type/exam"], exam: exam)
        let before = try entry(id)
        try run(NoteMigrate(course: Self.graphTheory))
        let merged = try entry(id)
        #expect(merged.tags == ["mine", "type/exam", "math/graph"])
        #expect(merged.kind == .examSummary && merged.examId == exam && merged.math == before.math && before.math == .asciimath)
    }

    /// An empty link the entry's kind reads is filled in.
    @Test func migrationFillsAnEmptyExam() throws {
        let exam = UUID()
        try run(ExamAdd(id: exam, course: Self.graphTheory, title: "모의고사"))
        let id = try entryWithFrontmatter("examId: \(exam)\n", body: "\n# 기출\n")
        try run(NoteMigrate(course: Self.graphTheory))
        #expect(try entry(id).examId == exam)
    }

    /// A frontmatter id other than the entry's goes; the entry's stays. Only when something points at the old one
    /// is the person told, since that link would now break.
    @Test func migrationKeepsTheEntrysID() throws {
        let old = UUID()
        let id = try entryWithFrontmatter("id: \(old)\ntags: [a]\n", body: "\n# 기출\n")
        let quiet = ActionContext(gist: gist, device: device, now: now, dryRun: true)
        try NoteMigrate(course: Self.graphTheory).run(quiet)
        #expect(quiet.notes.isEmpty)

        try run(NoteAdd(id: UUID(), course: Self.graphTheory, title: "모음", body: "[[note:\(old.uuidString.lowercased())|기출]]\n"))
        let preview = ActionContext(gist: gist, device: device, now: now, dryRun: true)
        try NoteMigrate(course: Self.graphTheory).run(preview)
        #expect(preview.notes == ["Notes/기출.md: frontmatter의 id \(old.uuidString) 대신 course.json 항목의 ID를 둡니다. 옛 ID를 가리키는 곳 1개(회차, 노트)는 손으로 고칩니다"])

        try run(NoteMigrate(course: Self.graphTheory))
        #expect(try entry(id).id == id && !file().notes.contains { $0.id == old })
        #expect(try text("Notes/기출.md") == "\n# 기출\n")
    }

    /// Only the frontmatter's Folio keys go; every byte after the block stays, and so do the keys Folio never wrote.
    @Test func migrationLeavesTheBodyAsItIs() throws {
        let body = "\n# 기출\n\n- [ ] 문제 $x^2$ ^q1\n\n```\n---\nid: not frontmatter\n```\n\n끝  \n\n"
        _ = try entryWithFrontmatter("tags: [a]\nscope: \"HW1, 기초\"\ndate: 2026-09-21\n", body: body)
        try run(NoteMigrate(course: Self.graphTheory))
        #expect(try text("Notes/기출.md") == "---\nscope: \"HW1, 기초\"\ndate: 2026-09-21\n---\n" + body)
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

    /// The fixture's rough note as notes were named before #273.
    func oldName() throws {
        try run(NoteMove(course: Self.graphTheory, note: "Notes/09-08(화) 매칭.md", to: "2주차-1"))
    }

    /// Session notes named before #273 take the date and subject; their headings and the links to them follow, and
    /// undoing the batch turns all three back.
    @Test func retitlingRenamesOldSessionNotesAndUndoTurnsThemBack() throws {
        let session = UUID(), review = UUID(), mine = UUID(), own = UUID()
        try oldName()
        try run(SessionAdd(id: session, course: Self.graphTheory, date: now))
        try linkUnit("Matchings", to: session)
        try run(NoteLink(course: Self.graphTheory, note: Self.note, kind: .rough, session: session))
        try run(NoteAdd(id: review, course: Self.graphTheory, title: "9주차-1 정리", kind: .review, session: session))
        try run(NoteAdd(id: mine, course: Self.graphTheory, title: "모음", body: "[[2주차-1]]와 [[9주차-1 정리#예시|예시]], [[다른 노트]]\n"))
        let other = UUID()
        try run(SessionAdd(id: other, course: Self.graphTheory, date: now.addingTimeInterval(86400)))
        try run(NoteAdd(id: own, course: Self.graphTheory, title: "내 필기", kind: .rough, session: other))

        // A note deleted in Finder keeps its entry; it is skipped rather than stopping the rest.
        let gone = UUID(), third = UUID()
        try run(SessionAdd(id: third, course: Self.graphTheory, date: now.addingTimeInterval(2 * 86400)))
        try run(NoteAdd(id: gone, course: Self.graphTheory, title: "9주차-3", kind: .rough, session: third))
        try FileManager.default.removeItem(at: try store().fileURL("Notes/9주차-3.md"))
        let before = try ["Notes/2주차-1.md", "Notes/9주차-1 정리.md", "Notes/모음.md"].map(text)

        let s = try #require(try file().sessions.first { $0.id == session })
        let rough = try file().noteTitle(for: s, kind: .rough, calendar: .current)
        #expect(rough.hasSuffix(" Matchings"))
        let dry = ActionContext(gist: gist, device: device, now: now, dryRun: true)
        try NoteRetitleSessions(course: Self.graphTheory).run(dry)
        #expect(dry.changes.filter { $0.kind == .moved }.count == 2 && dry.changes.contains { $0.kind == .changed && $0.path.hasSuffix("모음.md") })
        #expect(try text("Notes/2주차-1.md") == before[0])

        let batch = try #require(try run(NoteRetitleSessions(course: Self.graphTheory)).made)
        let paths = try Dictionary(uniqueKeysWithValues: file().notes.map { ($0.id, $0.path) })
        #expect(paths[Self.note] == "Notes/\(rough).md" && paths[review] == "Notes/\(rough) 정리.md")
        #expect(paths[own] == "Notes/내 필기.md" && paths[gone] == "Notes/9주차-3.md")
        #expect(try text("Notes/\(rough).md").hasPrefix("# \(rough)\n"))
        #expect(try text("Notes/\(rough) 정리.md").hasPrefix("# \(rough) 정리\n"))
        #expect(try text("Notes/모음.md") == "[[\(rough)]]와 [[\(rough) 정리#예시|예시]], [[다른 노트]]\n")
        #expect(try run(NoteRetitleSessions(course: Self.graphTheory)).made == nil)

        try run(CleanupUndo(batch: batch))
        let undone = try Dictionary(uniqueKeysWithValues: file().notes.map { ($0.id, $0.path) })
        #expect(undone[Self.note] == "Notes/2주차-1.md" && undone[review] == "Notes/9주차-1 정리.md")
        #expect(try ["Notes/2주차-1.md", "Notes/9주차-1 정리.md", "Notes/모음.md"].map(text) == before)
    }

    /// A link by ID keeps reaching the note whatever its name; the name it shows follows a rename while it is still the
    /// old title, in any course, and an undo turns it back. A name the writer chose stays.
    @Test func retitlingFollowsTheNamesOfLinksByID() throws {
        let session = UUID(), mine = UUID(), elsewhere = UUID()
        try oldName()
        let robotics = UUID(uuidString: "C0000000-0000-4000-8000-000000000003")!
        let id = Self.note.uuidString
        try run(SessionAdd(id: session, course: Self.graphTheory, date: now))
        try linkUnit("Matchings", to: session)
        try run(NoteLink(course: Self.graphTheory, note: Self.note, kind: .rough, session: session))
        let body = "[[note:\(id)|2주차-1]], [[note:\(id)#^c1|2주차-1]], [[note:\(id)|첫 수업]], [[note:\(id)]]\n"
        try run(NoteAdd(id: mine, course: Self.graphTheory, title: "모음", body: body))
        try run(NoteAdd(id: elsewhere, course: robotics, title: "참고", body: "![[note:\(id)#정의|2주차-1]]\n"))
        let roboticsStore = try ActionContext(gist: gist, device: device).store(robotics)
        let other = { try String(contentsOf: roboticsStore.fileURL("Notes/참고.md"), encoding: .utf8) }

        let batch = try #require(try run(NoteRetitleSessions(course: Self.graphTheory)).made)
        let rough = try #require(try file().notes.first { $0.id == Self.note }).path.dropFirst("Notes/".count).dropLast(".md".count)
        #expect(try text("Notes/모음.md") == "[[note:\(id)|\(rough)]], [[note:\(id)#^c1|\(rough)]], [[note:\(id)|첫 수업]], [[note:\(id)]]\n")
        #expect(try other() == "![[note:\(id)#정의|\(rough)]]\n")

        try run(CleanupUndo(batch: batch))
        #expect(try text("Notes/모음.md") == body)
        #expect(try other() == "![[note:\(id)#정의|2주차-1]]\n")
    }

    /// Renaming a note carries its entry, heading and the links to it by title and by ID along, in one batch that
    /// `cleanup undo` turns back whole. A name the writer gave a link stays.
    @Test func renamingANoteFollowsItsLinksAndUndoTurnsThemBack() throws {
        let id = Self.note.uuidString, mine = UUID()
        let body = "[[09-08(화) 매칭#Matching]], [[note:\(id)|09-08(화) 매칭]], [[note:\(id)|첫 수업]]\n"
        try run(NoteAdd(id: mine, course: Self.graphTheory, title: "모음", body: body))
        let before = try text("Notes/09-08(화) 매칭.md")

        let dry = ActionContext(gist: gist, device: device, now: now, dryRun: true)
        try NoteMove(course: Self.graphTheory, note: "Notes/09-08(화) 매칭.md", to: "매칭 기초").run(dry)
        #expect(dry.changes.contains(Change(.moved, "2026-3/EC4207 그래프 이론/Notes/09-08(화) 매칭.md", to: "2026-3/EC4207 그래프 이론/Notes/매칭 기초.md")))
        #expect(try text("Notes/09-08(화) 매칭.md") == before && dry.made == nil)

        let ran = try run(NoteMove(course: Self.graphTheory, note: "Notes/09-08(화) 매칭.md", to: "매칭 기초.md"))
        let batch = try #require(ran.made)
        #expect(ran.changes.contains { $0.touchesNotes })
        #expect(try file().notes.first { $0.id == Self.note }?.path == "Notes/매칭 기초.md")
        #expect(try text("Notes/매칭 기초.md").hasPrefix("# 매칭 기초\n"))
        #expect(try text("Notes/모음.md") == "[[매칭 기초#Matching]], [[note:\(id)|매칭 기초]], [[note:\(id)|첫 수업]]\n")
        #expect(try store().note(at: "Notes/09-08(화) 매칭.md") == nil)

        try run(CleanupUndo(batch: batch))
        #expect(try file().notes.first { $0.id == Self.note }?.path == "Notes/09-08(화) 매칭.md")
        #expect(try text("Notes/09-08(화) 매칭.md") == before && text("Notes/모음.md") == body)
    }

    /// Moved into a folder of Notes/, a note keeps its pictures, and a name another note of the course has gets ` 2`.
    @Test func movingANoteIntoAFolderKeepsItsPicturesAndAvoidsTakenNames() throws {
        let picture = UUID(), other = UUID()
        try run(NoteAdd(id: picture, course: Self.graphTheory, title: "그림 노트", body: "# 그림 노트\n\n![](assets/a.png)\n"))
        try run(NoteAdd(id: other, course: Self.graphTheory, title: "다른 노트"))
        try run(NoteMove(course: Self.graphTheory, note: "Notes/다른 노트.md", to: "정리/다른 노트"))
        #expect(try store().noteFolders() == ["", "정리"])

        let batch = try #require(try run(NoteMove(course: Self.graphTheory, note: "Notes/그림 노트.md", to: "정리/다른 노트")).made)
        #expect(try file().notes.first { $0.id == picture }?.path == "Notes/정리/다른 노트 2.md")
        #expect(try text("Notes/정리/다른 노트 2.md") == "# 다른 노트 2\n\n![](../assets/a.png)\n")

        try run(CleanupUndo(batch: batch))
        #expect(try text("Notes/그림 노트.md") == "# 그림 노트\n\n![](assets/a.png)\n")

        // Its own name is no other note's, so moving it alone keeps it.
        try run(NoteMove(course: Self.graphTheory, note: "Notes/그림 노트.md", to: "그림 노트"))
        #expect(try file().notes.first { $0.id == picture }?.path == "Notes/그림 노트.md")
    }

    /// A note moved in from an old folder has no entry until it is opened; its heading, pictures and the links to it
    /// follow all the same, and it still has no entry afterwards.
    @Test func aNoteWithoutAnEntryMovesWithItsLinks() throws {
        let notes = try store().url.appending(path: "Notes")
        try "# 그림\n\n![](assets/a.png)\n".write(to: notes.appending(path: "그림.md"), atomically: true, encoding: .utf8)
        try run(NoteAdd(id: UUID(), course: Self.graphTheory, title: "모음", body: "[[그림]]\n"))
        let entries = try file().notes
        let batch = try #require(try run(NoteMove(course: Self.graphTheory, note: "Notes/그림.md", to: "정리/도식")).made)
        #expect(try text("Notes/정리/도식.md") == "# 도식\n\n![](../assets/a.png)\n")
        #expect(try text("Notes/모음.md") == "[[도식]]\n")
        #expect(try file().notes == entries)
        try run(CleanupUndo(batch: batch))
        #expect(try text("Notes/그림.md") == "# 그림\n\n![](assets/a.png)\n" && text("Notes/모음.md") == "[[그림]]\n")
    }

    /// Builds the `.tex` note at `path` from `text`, as the app hands `note build` the PDF Tectonic wrote.
    func build(_ path: String, _ text: String) throws {
        let folder = TexEngine.outputFolder(for: try store().fileURL(path))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "\(UUID().uuidString).pdf")
        try Data(text.utf8).write(to: url)
        try run(NoteBuild(course: Self.graphTheory, note: path, pdf: url.path))
    }

    /// A `.tex` note renames as a markdown note does, and the PDF its build wrote takes the new title in the same batch,
    /// tracked under its new path, so the next build replaces it without asking. One undo puts both back.
    @Test func renamingATexNoteTakesItsBuiltPDFAlong() throws {
        let id = UUID()
        try run(NoteAdd(id: id, course: Self.graphTheory, title: "증명", format: .tex))
        try build("Notes/증명.tex", "%PDF mine")
        let material = try #require(try file().materials.first { $0.path == "Study/증명.pdf" }?.id)

        let dry = ActionContext(gist: gist, device: device, now: now, dryRun: true)
        try NoteMove(course: Self.graphTheory, note: "Notes/증명.tex", to: "정리/귀류법").run(dry)
        #expect(dry.changes.contains(Change(.moved, "2026-3/EC4207 그래프 이론/Study/증명.pdf", to: "2026-3/EC4207 그래프 이론/Study/귀류법.pdf")))
        #expect(try text("Study/증명.pdf") == "%PDF mine")

        let batch = try #require(try run(NoteMove(course: Self.graphTheory, note: "Notes/증명.tex", to: "정리/귀류법")).made)
        #expect(try file().notes.first { $0.id == id }?.path == "Notes/정리/귀류법.tex")
        #expect(try text("Notes/정리/귀류법.tex").contains("\\section*{귀류법}"))
        #expect(try text("Study/귀류법.pdf") == "%PDF mine" && !FileManager.default.fileExists(atPath: try store().fileURL("Study/증명.pdf").path))
        #expect(try file().materials.first { $0.id == material }?.path == "Study/귀류법.pdf")
        try build("Notes/정리/귀류법.tex", "%PDF again")
        #expect(try text("Study/귀류법.pdf") == "%PDF again")

        try run(CleanupUndo(batch: batch, course: Self.graphTheory))
        #expect(try file().notes.first { $0.id == id }?.path == "Notes/증명.tex")
        #expect(try text("Study/증명.pdf") == "%PDF again")
        #expect(try file().materials.first { $0.id == material }?.path == "Study/증명.pdf")
    }

    /// A PDF of the old title that Folio didn't build stays, and so does the built PDF when the new title's PDF is
    /// already there: nothing is overwritten.
    @Test func aPDFNotBuiltHereOrWithNowhereToGoStays() throws {
        try run(NoteAdd(id: UUID(), course: Self.graphTheory, title: "증명", format: .tex))
        let study = try store().fileURL("Study")
        try FileManager.default.createDirectory(at: study, withIntermediateDirectories: true)
        try Data("%PDF theirs".utf8).write(to: study.appending(path: "증명.pdf"))
        let note = try #require(try store().note(at: "Notes/증명.tex"))
        #expect(try store().builtPDF(of: note, in: file()) == nil)
        try run(NoteMove(course: Self.graphTheory, note: "Notes/증명.tex", to: "귀류법"))
        #expect(try text("Study/증명.pdf") == "%PDF theirs" && !FileManager.default.fileExists(atPath: study.appending(path: "귀류법.pdf").path))

        try build("Notes/귀류법.tex", "%PDF mine")
        try Data("%PDF other".utf8).write(to: study.appending(path: "대우.pdf"))
        let renamed = try #require(try store().note(at: "Notes/귀류법.tex"))
        let pdf = try #require(try store().builtPDFMove(of: renamed, to: store().fileURL("Notes/대우.tex"), in: file()))
        #expect(pdf.from == "Study/귀류법.pdf" && pdf.to == "Study/대우.pdf" && pdf.blocked)
        try run(NoteMove(course: Self.graphTheory, note: "Notes/귀류법.tex", to: "대우"))
        #expect(try text("Notes/대우.tex").contains("\\section*{대우}"))
        #expect(try text("Study/귀류법.pdf") == "%PDF mine" && text("Study/대우.pdf") == "%PDF other")
    }

    @Test func aNoteStaysInNotesAndKeepsItsFormat() throws {
        for to in ["assets/x", "Exports/x", ".hidden/x", "x.tex", "../x", "  "] {
            #expect(throws: ActionError.self, "\(to)") { try run(NoteMove(course: Self.graphTheory, note: "Notes/09-08(화) 매칭.md", to: to)) }
        }
        #expect(try run(NoteMove(course: Self.graphTheory, note: "Notes/09-08(화) 매칭.md", to: "09-08(화) 매칭")).made == nil)
        #expect(try file().notes.first { $0.id == Self.note }?.path == "Notes/09-08(화) 매칭.md")
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

    /// Becoming a unit note doesn't bring back units the note had as another kind, and leaving it drops them.
    @Test func changingKindDropsTheOtherKindsLinks() throws {
        let session = UUID(), unit = UUID(), other = UUID(), note = UUID()
        try run(SessionAdd(id: session, course: Self.graphTheory, date: now))
        try run(UnitAdd(id: unit, course: Self.graphTheory, title: "매칭"))
        try run(UnitAdd(id: other, course: Self.graphTheory, title: "트리"))
        try run(UnitLink(course: Self.graphTheory, unit: unit, sessions: [session]))
        try run(NoteAdd(id: note, course: Self.graphTheory, title: "필기", kind: .rough, session: session))
        try run(NoteLink(course: Self.graphTheory, note: note, kind: .unit, units: [other]))
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

    func linkUnit(_ title: String, to session: UUID) throws {
        let unit = UUID()
        try run(UnitAdd(id: unit, course: Self.graphTheory, title: title))
        try run(UnitLink(course: Self.graphTheory, unit: unit, sessions: [session]))
    }

    /// `import calendar` gives a free note named after a class's meeting to that class as its review note.
    @Test func importCalendarMakesTheNoteAReviewNote() throws {
        let note = UUID()
        try run(NoteAdd(id: note, course: Self.graphTheory, title: "평면 그래프"))
        let start = ISO8601DateFormatter().date(from: "2026-10-26T01:00:00Z")!
        try run(ImportCalendar(meetings: [CalendarMeeting(course: "EC4207 그래프 이론", start: start, end: start + 4500, room: "A229", topic: "평면 그래프")]))
        let s = try #require(try file().sessions.first { $0.reviewNoteId == note })
        #expect(try meta(note).kind == .review && meta(note).sessionId == s.id)
    }

    /// Rewrites replace, `set` actions of `Patch` fields set what they name, and the rest only add, so they never
    /// stand in for an earlier proposal.
    @Test func proposalTargetsFollowWhatEachCommandWrites() {
        #expect(Actions.targets[NoteWrite.command] == ProposalTarget(arguments: ["course", "note"], effect: .replaces(covers: [NoteEdit.command])))
        #expect(Actions.targets[ExamSet.command] == ProposalTarget(arguments: ["course", "exam"], effect: .sets))
        #expect(Actions.targets[NoteLink.command]?.effect == .sets)
        #expect(Actions.targets[MaterialWrite.command]?.effect == .replaces(covers: []))
        for additive in [NoteEdit.command, NoteAdd.command, ExamAdd.command, SessionAdd.command, ScoreAdd.command, QuizRecord.command,
                         ExamRemove.command, MaterialTrack.command, UnitLink.command] {
            #expect(Actions.targets[additive] == nil, "\(additive)")
        }
    }
}
