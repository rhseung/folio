@testable import FolioCLI
import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

struct MaterialNoteStudyTests {
    let h = Harness()
    let course = Harness.graphTheory
    static let track = ["material", "track", "EC4207"]
    static let unit = UUID(uuidString: "A0000000-0000-4000-8000-0000000000B1")!
    static let addUnit = ["run", "unit", "add", "--input", #"{"course":"EC4207","title":"매칭","id":"\#(unit.uuidString)"}"#]
    static let card = UUID(uuidString: "A0000000-0000-4000-8000-0000000000C1")!
    static let set = UUID(uuidString: "A0000000-0000-4000-8000-0000000000D1")!
    static let addSet = ["problem-set", "add", "EC4207", "Exercise 1", "--problems", "1", "3a", "--id", set.uuidString]
    static let noteID = UUID(uuidString: "6f1d2c4e-8a3b-4f5e-9c1d-2b7a8e0f3d41")!
    static let exam = UUID(uuidString: "A0000000-0000-4000-8000-0000000000E7")!
    static let addExam = ["exam", "add", "EC4207", "Midterm", "--id", exam.uuidString]

    func material(_ gist: GISTStore, _ name: String) throws -> UUID {
        try #require(try h.file(gist).materials.first { $0.path.hasSuffix(name) }).id
    }

    /// A file outside the fixture, shared by both copies.
    func scratch(_ name: String, _ text: String) throws -> String {
        let url = FileManager.default.temporaryDirectory.appending(path: "folio-cli-\(UUID().uuidString)").appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    func cardsFile() throws -> String {
        let card = QuizCard(id: Self.card, device: h.device, at: h.now, unitId: Self.unit, type: .free, category: .definition,
                            prompt: "최대 매칭의 정의", answer: "더 큰 매칭이 없는 매칭")
        return try scratch("cards.json", String(decoding: try JSONEncoder.folio.encode([card]), as: UTF8.self))
    }

    // MARK: Materials

    @Test func trackRegistersFilesAndAssignmentFolders() throws {
        try h.expectSame(["material", "track"]) { _ in MaterialTrack(course: nil) }
        let gist = try Harness.fixtureCopy()
        _ = h.cli(["material", "track"], gist: gist)
        let f = try h.file(GISTStore(url: gist))
        #expect(f.assignments.map(\.title).sorted() == ["HW03", "SP01"])
        #expect(f.assignments.allSatisfy { $0.status == .todo })
        #expect(f.materials.contains { $0.path == "Lectures/05_Matchings.pdf" })
        // Spring 2026 ended before the pinned now: its homework was handed in.
        let past = try h.file(GISTStore(url: gist), UUID(uuidString: "C0000000-0000-4000-8000-000000000001")!)
        #expect(past.assignments.map(\.title) == ["HW01"])
        #expect(past.assignments.first?.status == .submitted)
    }

    @Test func linkSession() throws {
        try h.expectSame(["material", "link", "EC4207/05_Matchings.pdf", "10-28", "--pages", "3-12"], setup: [Self.track, SessionCommandTests.add]) { gist in
            MaterialLinkSession(course: course, material: try material(gist, "05_Matchings.pdf"), session: SessionCommandTests.id, firstPage: 3, lastPage: 12)
        }
    }

    @Test func sessionProgress() throws {
        try h.expectSame(["session", "progress", "EC4207/10-28", "05_Matchings.pdf:3-12", "Problems.pdf:7"], setup: [Self.track, SessionCommandTests.add]) { gist in
            SessionProgress(course: course, session: SessionCommandTests.id, ranges: [
                SessionMaterial(materialId: try material(gist, "05_Matchings.pdf"), firstPage: 3, lastPage: 12),
                SessionMaterial(materialId: try material(gist, "Study/Problems.pdf"), firstPage: 7, lastPage: 7),
            ])
        }
        let gist = try Harness.fixtureCopy()
        for setup in [Self.track, SessionCommandTests.add] { _ = h.cli(setup, gist: gist) }
        #expect(h.cli(["session", "progress", "EC4207/10-28", "05_Matchings.pdf"], gist: gist).code == Exit.usage.rawValue)
        // A backward range is refused whole: the other file isn't written either.
        #expect(h.cli(["session", "progress", "EC4207/10-28", "Problems.pdf:1-2", "05_Matchings.pdf:12-3"], gist: gist).code != 0)
        #expect(try h.file(GISTStore(url: gist)).sessions.first { $0.id == SessionCommandTests.id }?.materials.isEmpty == true)
        #expect(h.cli(["session", "progress", "EC4207/10-28", "05_Matchings.pdf:3-12"], gist: gist).code == 0)
        #expect(h.cli(["session", "show", "EC4207/10-28"], gist: gist).out.contains("05_Matchings.pdf p.3-12"))
    }

    @Test func sessionWrapUp() throws {
        try h.expectSame(["session", "wrap-up", "EC4207/10-28", "05_Matchings.pdf:3-12", "--unit", "매칭", "--attendance", "late"],
                         setup: [Self.track, SessionCommandTests.add, Self.addUnit]) { gist in
            SessionWrapUp(course: course, session: SessionCommandTests.id,
                          ranges: [SessionMaterial(materialId: try material(gist, "05_Matchings.pdf"), firstPage: 3, lastPage: 12)],
                          units: .set([Self.unit]), attendance: .set(.late))
        }
        // Given nothing, what the class has stays and it is only marked wrapped up.
        let gist = try Harness.fixtureCopy()
        for setup in [Self.track, SessionCommandTests.add, Self.addUnit] { _ = h.cli(setup, gist: gist) }
        #expect(h.cli(["session", "wrap-up", "EC4207/10-28", "--unit", "매칭", "--attendance", "absent"], gist: gist).code == 0)
        #expect(h.cli(["session", "wrap-up", "EC4207/10-28"], gist: gist).code == 0)
        let f = try h.file(GISTStore(url: gist))
        let s = try #require(f.sessions.first { $0.id == SessionCommandTests.id })
        #expect(s.isWrappedUp)
        #expect(s.unitIds == [Self.unit])
        let entry = try #require(f.attendance.first { $0.sessionId == s.id })
        #expect(entry.state == .absent)
        // The same state again keeps the entry as it was rather than writing it anew.
        #expect(h.cli(["session", "wrap-up", "EC4207/10-28", "--attendance", "absent"], gist: gist).code == 0)
        #expect(try h.file(GISTStore(url: gist)).attendance.filter { $0.sessionId == s.id }.map(\.id) == [entry.id])
    }

    @Test func linkUnit() throws {
        try h.expectSame(["material", "link-unit", "EC4207/05_Matchings.pdf", "매칭"], setup: [Self.track, Self.addUnit]) { gist in
            MaterialLinkUnit(course: course, material: try material(gist, "05_Matchings.pdf"), unit: Self.unit, linked: true)
        }
    }

    @Test func linkExam() throws {
        try h.expectSame(["material", "link-exam", "EC4207/Problems.pdf", "Midterm"], setup: [Self.track, Self.addExam]) { gist in
            MaterialLinkExam(course: course, material: try material(gist, "Study/Problems.pdf"), exam: Self.exam, linked: true)
        }
    }

    @Test func newFile() throws {
        try h.expectSame(["material", "new", "EC4207", "Assignments/HW03", "hw3.tex"], setup: [Self.track]) { _ in
            MaterialNew(course: course, folder: "Assignments/HW03", name: "hw3.tex")
        }
    }

    @Test func statusOfSeveralNeedsConfirmation() throws {
        let gist = try Harness.fixtureCopy()
        _ = h.cli(Self.track, gist: gist)
        #expect(h.cli(["material", "status", "ignored", "EC4207/Seating.pdf", "Guideline.pdf"], gist: gist).code == Exit.needsConfirmation.rawValue)
        try h.expectSame(["material", "status", "ignored", "EC4207/Seating.pdf", "Guideline.pdf", "--yes"], setup: [Self.track]) { gist in
            MaterialStatusSet(course: course, status: .ignored, materials: [try material(gist, "Seating.pdf"), try material(gist, "Guideline.pdf")])
        }
    }

    @Test func kindOfSeveralNeedsConfirmation() throws {
        let gist = try Harness.fixtureCopy()
        _ = h.cli(Self.track, gist: gist)
        #expect(h.cli(["material", "kind", "submission", "EC4207/Seating.pdf", "Guideline.pdf"], gist: gist).code == Exit.needsConfirmation.rawValue)
        try h.expectSame(["material", "kind", "submission", "EC4207/Seating.pdf", "Guideline.pdf", "--yes"], setup: [Self.track]) { gist in
            MaterialKindSet(course: course, kind: .submission, materials: [try material(gist, "Seating.pdf"), try material(gist, "Guideline.pdf")])
        }
    }

    @Test func relink() throws {
        try h.expectSame(["material", "relink", "EC4207/Seating.pdf", "Exams/Midterm/Guideline.pdf"], setup: [Self.track]) { gist in
            let store = try ActionContext(gist: gist, device: h.device).store(course)
            return MaterialRelink(course: course, material: try material(gist, "Seating.pdf"), file: store.url.appending(path: "Exams/Midterm/Guideline.pdf").path)
        }
    }

    @Test func writeText() throws {
        let text = "\\documentclass{article}\n"
        let file = try scratch("Problems.tex", text)
        try h.expectSame(["material", "write", "EC4207/Problems.tex", "--file", file], setup: [Self.track]) { gist in
            MaterialWrite(course: course, material: try material(gist, "Problems.tex"), text: text)
        }
    }

    @Test func writeRefusesAStaleHash() throws {
        let gist = try Harness.fixtureCopy()
        _ = h.cli(Self.track, gist: gist)
        let file = try scratch("Problems.tex", "x")
        #expect(h.cli(["material", "write", "EC4207/Problems.tex", "--file", file, "--expect", "00"], gist: gist).code == Exit.conflict.rawValue)
    }

    /// The file changes on another device after tracking; `material show --json` reads it again, so its hash still
    /// opens the write.
    @Test func writeTakesTheHashShowReadsNow() throws {
        let gist = try Harness.fixtureCopy()
        _ = h.cli(Self.track, gist: gist)
        let tex = gist.appending(path: "2026-3/EC4207 그래프 이론/Study/Problems.tex")
        try "% 다른 기기에서 고침\n".write(to: tex, atomically: true, encoding: .utf8)
        let shown = try #require(try JSONSerialization.jsonObject(with: Data(h.cli(["material", "show", "EC4207/Problems.tex", "--json"], gist: gist).out.utf8)) as? [String: Any])
        #expect(shown["text"] as? String == "% 다른 기기에서 고침\n" && shown["path"] as? String == "Study/Problems.tex")
        let hash = try #require(shown["contentHash"] as? String)
        let file = try scratch("Problems.tex", "x")
        #expect(h.cli(["material", "write", "EC4207/Problems.tex", "--file", file, "--expect", hash], gist: gist).code == 0)
        #expect(try String(contentsOf: tex, encoding: .utf8) == "x")
    }

    /// The format the app opens a file by, so an agent knows a PDF from a slide deck without guessing from the name.
    @Test func showReportsTheFormat() throws {
        let gist = try Harness.fixtureCopy()
        _ = h.cli(Self.track, gist: gist)
        let pdf = try #require(try JSONSerialization.jsonObject(with: Data(h.cli(["material", "show", "EC4207/Seating.pdf", "--json"], gist: gist).out.utf8)) as? [String: Any])
        #expect(pdf["format"] as? String == "pdf" && pdf["text"] == nil)
        let tex = try #require(try JSONSerialization.jsonObject(with: Data(h.cli(["material", "show", "EC4207/Problems.tex", "--json"], gist: gist).out.utf8)) as? [String: Any])
        #expect(tex["format"] as? String == "tex" && tex["text"] != nil)
        #expect(h.cli(["material", "show", "EC4207/Seating.pdf"], gist: gist).out.contains("pdf"))
    }

    @Test(.enabled(if: TexEngine.locate() != nil, "Tectonic is not installed"))
    func buildTex() throws {
        let write = ["material", "write", "EC4207/Problems.tex", "--file",
                     try scratch("Problems.tex", "\\documentclass{article}\n\\begin{document}\nHi\n\\end{document}\n")]
        try h.expectSame(["material", "build", "EC4207/Problems.tex", "--overwrite"], setup: [Self.track, write]) { gist in
            MaterialBuild(course: course, material: try material(gist, "Problems.tex"), overwrite: true)
        }
    }

    @Test func untrack() throws {
        try h.expectSame(["material", "untrack", "EC4207/Seating.pdf"], setup: [Self.track]) { gist in
            MaterialUntrack(course: course, material: try material(gist, "Seating.pdf"))
        }
    }

    @Test func importCopiesAndLinks() throws {
        let file = try scratch("Coloring.pdf", "pdf")
        try h.expectSame(["material", "import", "EC4207", file, "--folder", "Lectures", "--session", "10-28"],
                         setup: [Self.track, SessionCommandTests.add]) { _ in
            MaterialImport(course: course, items: [ImportItem(file: file, folder: "Lectures", session: SessionCommandTests.id)])
        }
    }

    @Test func moveNeedsConfirmation() throws {
        let gist = try Harness.fixtureCopy()
        _ = h.cli(Self.track, gist: gist)
        #expect(h.cli(["material", "mv", "EC4207/Seating.pdf", "Exams/Midterm/자리.pdf"], gist: gist).code == Exit.needsConfirmation.rawValue)
        try h.expectSame(["material", "mv", "EC4207/Seating.pdf", "Exams/Midterm/자리.pdf", "--yes"], setup: [Self.track]) { gist in
            MaterialMove(course: course, material: try material(gist, "Seating.pdf"), to: "Exams/Midterm/자리.pdf")
        }
    }

    @Test func trash() throws {
        try h.expectSame(["material", "rm", "EC4207/Seating.pdf", "--yes"], setup: [Self.track]) { gist in
            MaterialTrash(course: course, material: try material(gist, "Seating.pdf"))
        }
    }

    // MARK: Cleanup

    static let move = PlannedMove(from: "2026-3/EC4207 그래프 이론/Exams/Midterm/Seating.pdf", to: "2026-3/EC4207 그래프 이론/Exams/Midterm/Seat.pdf")

    func planFile() throws -> String {
        let url = URL(filePath: try scratch("plan.json", ""))
        try StoredDocument(new: CleanupPlan(moves: [Self.move], skipped: [])).write(to: url)
        return url.path
    }

    @Test func cleanupApply() throws {
        let backup = FileManager.default.temporaryDirectory.appending(path: "folio-cli-backup-\(UUID().uuidString)").path
        try h.expectSame(["cleanup", "apply", "--plan", try planFile(), "--backup", backup, "--yes"]) { _ in CleanupApply(moves: [Self.move]) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: backup).count == 1)
    }

    /// A moved file keeps its material, which then gets the exam link and past exam mark the plan carried.
    @Test func cleanupApplyLinksMovedFiles() throws {
        let gist = try Harness.fixtureCopy()
        _ = h.cli(Self.track, gist: gist)
        _ = h.cli(Self.addExam, gist: gist)
        let store = GISTStore(url: gist)
        let before = try material(store, "Exercises/Exercise 1.pdf")
        let ec = "2026-3/EC4207 그래프 이론"
        try h.direct(CleanupApply(moves: [
            PlannedMove(from: "\(ec)/Exercises/Exercise 1.pdf", to: "\(ec)/Study/Exercise 1.pdf", exam: "Midterm"),
            PlannedMove(from: "\(ec)/Exams/Midterm/Seating.pdf", to: "\(ec)/Inherited/Seating.pdf", kind: .pastExam),
        ]), gist: gist)
        let f = try h.file(store)
        let study = try #require(f.materials.first { $0.path == "Study/Exercise 1.pdf" })
        #expect(study.id == before && study.examIds == [Self.exam] && study.role == .study)
        #expect(f.materials.first { $0.path == "Inherited/Seating.pdf" }.map { ($0.kind, $0.role) }! == (.pastExam, .inherited))
        #expect(f.materials(for: try #require(f.exams.first { $0.id == Self.exam })).map(\.path).contains("Study/Exercise 1.pdf"))
    }

    @Test func cleanupApplyNotesLinksToMissingExams() throws {
        let gist = try Harness.fixtureCopy()
        _ = h.cli(Self.track, gist: gist)
        let ec = "2026-3/EC4207 그래프 이론"
        let ctx = ActionContext(gist: GISTStore(url: gist), device: h.device, now: h.now)
        try CleanupApply(moves: [PlannedMove(from: "\(ec)/Exercises/Exercise 1.pdf", to: "\(ec)/Study/Exercise 1.pdf", exam: "Quiz9")]).run(ctx)
        #expect(ctx.notes.contains { $0.contains("Study/Exercise 1.pdf") && $0.contains("Quiz9") })
        #expect(try h.file(GISTStore(url: gist)).materials.first { $0.path == "Study/Exercise 1.pdf" }?.examIds == [])
    }

    @Test func cleanupRemovesEmptyExamFolders() throws {
        let gist = try Harness.fixtureCopy()
        let empty = "2026-3/EC4207 그래프 이론/Exams/Quiz1"
        try FileManager.default.createDirectory(at: gist.appending(path: empty), withIntermediateDirectories: true)
        try h.direct(CleanupApply(moves: [], removals: [empty]), gist: gist)
        #expect(!FileManager.default.fileExists(atPath: gist.appending(path: empty).path))
        try h.direct(CleanupUndo(batch: try MoveJournal.records(in: gist).first!.batch), gist: gist)
        #expect(FileManager.default.fileExists(atPath: gist.appending(path: empty).path))
    }

    @Test func cleanupUndo() throws {
        let (a, b) = (try Harness.fixtureCopy(), try Harness.fixtureCopy())
        let batch = { (gist: URL) in try MoveJournal.records(in: gist).first!.batch }
        try h.direct(CleanupApply(moves: [Self.move]), gist: a)
        try h.direct(CleanupApply(moves: [Self.move]), gist: b)
        #expect(h.cli(["cleanup", "undo", try batch(a).uuidString], gist: a).code == Exit.needsConfirmation.rawValue)
        #expect(h.cli(["cleanup", "undo", try batch(a).uuidString, "--yes"], gist: a).code == 0)
        try h.direct(CleanupUndo(batch: try batch(b)), gist: b)
        let (fa, fb) = (try Harness.files(a), try Harness.files(b))
        #expect(fa.keys.sorted() == fb.keys.sorted())
        #expect(fa.keys.contains { $0.hasSuffix("Midterm/Seating.pdf") })
        for (path, data) in fa { #expect(Harness.canonical(fb[path]) == Harness.canonical(data), "\(path)") }
    }

    // MARK: Notes

    @Test func noteAdd() throws {
        let id = UUID(uuidString: "A0000000-0000-4000-8000-0000000000E1")!
        try h.expectSame(["note", "add", "EC4207", "매칭 정리", "--kind", "topic", "--id", id.uuidString]) { _ in
            NoteAdd(id: id, course: course, title: "매칭 정리", kind: .unit)
        }
    }

    @Test func noteWrite() throws {
        let text = "# 09-08(화) 매칭\n\n고쳐 씀\n"
        try h.expectSame(["note", "write", "EC4207/09-08", "--file", try scratch("note.md", text)]) { _ in
            NoteWrite(course: course, note: "Notes/09-08(화) 매칭.md", text: text)
        }
    }

    @Test func noteEdit() throws {
        try h.expectSame(["note", "edit", "EC4207/09-08", "--old", "Matching", "--new", "매칭", "--old", "pairwise", "--new", "서로",
                          "--append", "질문"]) { _ in
            NoteEdit(course: course, note: "Notes/09-08(화) 매칭.md",
                     replacements: [.init(old: "Matching", new: "매칭"), .init(old: "pairwise", new: "서로")], append: "질문")
        }
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(["note", "edit", "EC4207/09-08", "--old", "Matching"], gist: gist).code == Exit.usage.rawValue)
        #expect(h.cli(["note", "edit", "EC4207/09-08", "--old", "없는 글", "--new", "x"], gist: gist).code == Exit.conflict.rawValue)
    }

    /// Writes a note file straight into Notes/, as another editor would, so it has no entry in course.json.
    func drop(_ gist: URL, _ name: String, _ text: String) throws {
        let store = try ActionContext(gist: GISTStore(url: gist), device: h.device, now: h.now).store(course)
        try text.write(to: store.url.appending(path: "Notes/\(name)"), atomically: true, encoding: .utf8)
    }

    @Test func noteAdopt() throws {
        try h.expectSame(["note", "adopt", "EC4207/바깥"], prepare: { try drop($0, "바깥.md", "# 바깥에서 만든 노트\n") }) { _ in
            NoteAdopt(course: course, note: "Notes/바깥.md")
        }
    }

    @Test(.enabled(if: TexEngine.locate() != nil, "Tectonic is not installed"))
    func noteBuild() throws {
        let tex = "\\documentclass{article}\n\\begin{document}\nHi\n\\end{document}\n"
        let id = UUID()
        let prepare = { (gist: URL) in
            try NoteAdd(id: id, course: course, title: "증명", format: .tex).run(ActionContext(gist: GISTStore(url: gist), device: h.device, now: h.now))
            try drop(gist, "증명.tex", tex)
        }
        try h.expectSame(["note", "build", "EC4207/증명"], prepare: prepare) { _ in
            NoteBuild(course: course, note: "Notes/증명.tex")
        }
    }

    @Test func noteMigrate() throws {
        let text = "---\nid: 0a1b2c3d-0000-4000-8000-000000000001\nkind: review\ntags: [그래프]\nauthor: 나\n---\n\n# 예전\n"
        try h.expectSame(["note", "migrate", "EC4207"], prepare: { try drop($0, "예전.md", text) }) { _ in
            NoteMigrate(course: course)
        }
    }

    @Test func noteRetitle() throws {
        // The fixture's note as notes were named before #273.
        let setup = [SessionCommandTests.add, ["note", "mv", "EC4207/09-08", "2주차-1", "--yes"],
                     ["note", "link", "EC4207/2주차-1", "--kind", "rough", "--session", "10-28"]]
        try h.expectSame(["note", "retitle", "EC4207", "--yes"], setup: setup) { _ in
            NoteRetitleSessions(course: course)
        }
    }

    @Test func noteLink() throws {
        try h.expectSame(["note", "link", "EC4207/09-08", "--kind", "review", "--session", "10-28"], setup: [SessionCommandTests.add]) { _ in
            NoteLink(course: course, note: Self.noteID, kind: .review, session: SessionCommandTests.id)
        }
    }

    static let laterSession = UUID(uuidString: "A0000000-0000-4000-8000-000000000002")!
    static let reviewSetup = [SessionCommandTests.add, ["session", "add", "EC4207", "--date", "2026-10-30 10:30", "--id", laterSession.uuidString],
                              ["note", "link", "EC4207/09-08", "--kind", "review", "--session", "10-28"]]

    @Test func noteLinkSessions() throws {
        try h.expectSame(["note", "link-sessions", "EC4207/09-08", "10-28", "10-30"], setup: Self.reviewSetup) { _ in
            NoteLinkSessions(course: course, note: Self.noteID, sessions: [SessionCommandTests.id, Self.laterSession])
        }
    }

    @Test func noteUnlinkSession() throws {
        try h.expectSame(["note", "unlink-session", "EC4207/09-08", "10-28"], setup: Self.reviewSetup) { _ in
            NoteUnlinkSession(course: course, note: Self.noteID, session: SessionCommandTests.id)
        }
    }

    @Test func noteRemove() throws {
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(["note", "rm", "EC4207/09-08"], gist: gist).code == Exit.needsConfirmation.rawValue)
        try h.expectSame(["note", "rm", "EC4207/09-08", "--yes"]) { _ in NoteRemove(course: course, note: "Notes/09-08(화) 매칭.md") }
    }

    @Test func noteMove() throws {
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(["note", "mv", "EC4207/09-08", "정리/매칭"], gist: gist).code == Exit.needsConfirmation.rawValue)
        try h.expectSame(["note", "mv", "EC4207/09-08", "정리/매칭", "--yes"]) { _ in
            NoteMove(course: course, note: "Notes/09-08(화) 매칭.md", to: "정리/매칭")
        }
    }

    // MARK: Quiz and problem sets

    @Test func quizAdd() throws {
        let file = try cardsFile()
        let cards = try JSONDecoder.folio.decode([QuizCard].self, from: Data(contentsOf: URL(filePath: file)))
        try h.expectSame(["quiz", "add", "EC4207", "--file", file], setup: [Self.addUnit]) { _ in QuizCardSave(course: course, cards: cards) }
    }

    @Test func quizRemove() throws {
        try h.expectSame(["quiz", "rm", "EC4207/매칭", Self.card.uuidString, "--yes"], setup: [Self.addUnit, ["quiz", "add", "EC4207", "--file", try cardsFile()]]) { _ in
            QuizCardRemove(course: course, unit: Self.unit, card: Self.card)
        }
    }

    @Test func quizRecord() throws {
        try h.expectSame(["quiz", "record", "EC4207/매칭", "최대 매칭의 정의", "correct"], setup: [Self.addUnit, ["quiz", "add", "EC4207", "--file", try cardsFile()]]) { _ in
            QuizRecord(course: course, attempt: QuizAttemptEvent(cardId: Self.card, verdict: .correct, grader: .self))
        }
    }

    @Test func problemSetAdd() throws {
        try h.expectSame(Self.addSet) { _ in
            ProblemSetSave(course: course, set: ProblemSet(id: Self.set, device: h.device, at: h.now, title: "Exercise 1", problems: [.init(number: "1"), .init(number: "3a")]))
        }
    }

    @Test func problemSetRemove() throws {
        try h.expectSame(["problem-set", "rm", "EC4207/Exercise 1", "--yes"], setup: [Self.addSet]) { _ in ProblemSetRemove(course: course, set: Self.set) }
    }

    @Test func problemSetLink() throws {
        try h.expectSame(["problem-set", "link", "EC4207/Exercise 1", "3a", "매칭"], setup: [Self.addUnit, Self.addSet]) { _ in
            ProblemLinkUnit(course: course, set: Self.set, number: "3a", unit: Self.unit, linked: true)
        }
    }

    @Test func problemSetRecord() throws {
        try h.expectSame(["problem-set", "record", "EC4207/Exercise 1", "3a", "wrong"], setup: [Self.addSet]) { _ in
            ProblemRecord(course: course, attempt: ProblemAttemptEvent(problemSetId: Self.set, number: "3a", verdict: .wrong))
        }
    }

    // MARK: Review

    @Test func reviewRecord() throws {
        try h.expectSame(["review", "record", "EC4207/매칭", "good", "--start", "2026-10-28 20:00", "--end", "2026-10-28 20:40"], setup: [Self.addUnit]) { _ in
            ReviewRecord(course: course, unit: Self.unit, result: .good, start: DateArg(argument: "2026-10-28 20:00")!.date, end: DateArg(argument: "2026-10-28 20:40")!.date)
        }
    }

    @Test func reviewSkip() throws {
        try h.expectSame(["review", "skip", "EC4207/매칭"], setup: [Self.addUnit]) { _ in
            ReviewSkip(units: [.init(course: course, unit: Self.unit)])
        }
    }

    @Test func reviewSkipWithTheTimeOpen() throws {
        try h.expectSame(["review", "skip", "EC4207/매칭", "--start", "2026-10-28 20:00", "--end", "2026-10-28 20:05"], setup: [Self.addUnit]) { _ in
            ReviewSkip(units: [.init(course: course, unit: Self.unit)], start: DateArg(argument: "2026-10-28 20:00")!.date, end: DateArg(argument: "2026-10-28 20:05")!.date)
        }
    }
}
