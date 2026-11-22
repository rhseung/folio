import FolioActions
import FolioCore
import FolioDomain
import FolioStorage
import Foundation
import Testing

@testable import FolioCLI

struct MaterialNoteStudyTests {
    let h = Harness()
    let course = Harness.graphTheory
    static let track = ["material", "track", "EC4207"]
    static let unit = UUID(uuidString: "A0000000-0000-4000-8000-0000000000B1")!
    static let addUnit = ["run", "unit", "add", "--input", #"{"course":"EC4207","title":"매칭","id":"\#(unit.uuidString)"}"#]
    static let card = UUID(uuidString: "A0000000-0000-4000-8000-0000000000C1")!
    static let set = UUID(uuidString: "A0000000-0000-4000-8000-0000000000D1")!
    static let addSet = ["problem-set", "add", "EC4207", "Exercise 1", "1", "3a", "--id", set.uuidString]
    static let noteID = UUID(uuidString: "6f1d2c4e-8a3b-4f5e-9c1d-2b7a8e0f3d41")!
    static let exam = UUID(uuidString: "A0000000-0000-4000-8000-0000000000E7")!
    static let addExam = ["exam", "add", "EC4207", "Midterm", "--id", exam.uuidString]

    func material(_ gist: GISTStore, _ name: String) throws -> UUID {
        try #require(try h.file(gist).materials.first { $0.path.hasSuffix(name) }).id
    }

    func scratch(_ name: String, _ text: String) throws -> String {
        let url = FileManager.default.temporaryDirectory.appending(path: "folio-cli-\(UUID().uuidString)").appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    func cardsFile() throws -> String {
        let card = StudyCard(id: Self.card, device: h.device, at: h.now, unitId: Self.unit, front: "최대 매칭의 정의", back: "더 큰 매칭이 없는 매칭")
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

        let past = try h.file(GISTStore(url: gist), UUID(uuidString: "C0000000-0000-4000-8000-000000000001")!)
        #expect(past.assignments.map(\.title) == ["HW01"])
        #expect(past.assignments.first?.status == .submitted)
    }

    @Test func trackFilesOnlyLeavesAssignmentFoldersAlone() throws {
        try h.expectSame(["material", "track", "EC4207", "--files-only"]) { _ in MaterialTrack(course: course, assignments: false) }
        let gist = try Harness.fixtureCopy()
        let before = try h.file(GISTStore(url: gist)).assignments
        _ = h.cli(["material", "track", "EC4207", "--files-only"], gist: gist)
        let f = try h.file(GISTStore(url: gist))
        #expect(f.assignments == before)
        #expect(f.materials.contains { $0.path == "Assignments/HW03/26h3.pdf" })
        #expect(f.materials.contains { $0.path == "Lectures/05_Matchings.pdf" })
    }

    @Test func linkSession() throws {
        try h.expectSame(
            ["material", "link", "EC4207/05_Matchings.pdf", "10-28", "--pages", "3-12"], setup: [Self.track, SessionCommandTests.add]
        ) { gist in
            MaterialLinkSession(
                course: course, material: try material(gist, "05_Matchings.pdf"), session: SessionCommandTests.id, firstPage: 3,
                lastPage: 12)
        }
    }

    @Test func sessionProgress() throws {
        try h.expectSame(
            ["session", "progress", "EC4207/10-28", "05_Matchings.pdf:3-12", "Problems.pdf:7"],
            setup: [Self.track, SessionCommandTests.add]
        ) { gist in
            SessionProgress(
                course: course, session: SessionCommandTests.id,
                ranges: [
                    SessionMaterial(materialId: try material(gist, "05_Matchings.pdf"), firstPage: 3, lastPage: 12),
                    SessionMaterial(materialId: try material(gist, "Study/Problems.pdf"), firstPage: 7, lastPage: 7),
                ])
        }
        let gist = try Harness.fixtureCopy()
        for setup in [Self.track, SessionCommandTests.add] { _ = h.cli(setup, gist: gist) }
        #expect(h.cli(["session", "progress", "EC4207/10-28", "05_Matchings.pdf"], gist: gist).code == Exit.usage.rawValue)

        #expect(h.cli(["session", "progress", "EC4207/10-28", "Problems.pdf:1-2", "05_Matchings.pdf:12-3"], gist: gist).code != 0)
        #expect(try h.file(GISTStore(url: gist)).sessions.first { $0.id == SessionCommandTests.id }?.materials.isEmpty == true)
        #expect(h.cli(["session", "progress", "EC4207/10-28", "05_Matchings.pdf:3-12"], gist: gist).code == 0)
        #expect(h.cli(["session", "show", "EC4207/10-28"], gist: gist).out.contains("05_Matchings.pdf p.3-12"))
    }

    @Test func sessionWrapUp() throws {
        try h.expectSame(
            ["session", "wrap-up", "EC4207/10-28", "05_Matchings.pdf:3-12", "--unit", "매칭", "--attendance", "late"],
            setup: [Self.track, SessionCommandTests.add, Self.addUnit]
        ) { gist in
            SessionWrapUp(
                course: course, session: SessionCommandTests.id,
                ranges: [SessionMaterial(materialId: try material(gist, "05_Matchings.pdf"), firstPage: 3, lastPage: 12)],
                units: .set([Self.unit]), attendance: .set(.late))
        }
        let gist = try Harness.fixtureCopy()
        for setup in [Self.track, SessionCommandTests.add, Self.addUnit] { _ = h.cli(setup, gist: gist) }
        #expect(h.cli(["session", "wrap-up", "EC4207/10-28", "--unit", "매칭", "--attendance", "absent"], gist: gist).code == 0)

        #expect(try h.file(GISTStore(url: gist)).sessions.first { $0.id == SessionCommandTests.id }?.isWrappedUp == false)

        #expect(h.cli(["session", "wrap-up", "EC4207/10-28", "--date", "2026-10-27 19:00"], gist: gist).code == 0)
        let f = try h.file(GISTStore(url: gist))
        let s = try #require(f.sessions.first { $0.id == SessionCommandTests.id })
        #expect(s.isWrappedUp)
        #expect(s.unitIds == [Self.unit])
        let entry = try #require(f.attendance.first { $0.sessionId == s.id })
        #expect(entry.state == .absent)

        #expect(h.cli(["session", "wrap-up", "EC4207/10-27", "--attendance", "absent"], gist: gist).code == 0)
        #expect(try h.file(GISTStore(url: gist)).attendance.filter { $0.sessionId == s.id }.map(\.id) == [entry.id])
    }

    @Test func sessionWrapUpUnlinks() throws {
        let linked = ["material", "link", "EC4207/05_Matchings.pdf", "10-28", "--pages", "3-12"]
        let setup = [Self.track, SessionCommandTests.add, linked]
        try h.expectSame(["session", "wrap-up", "EC4207/10-28", "Problems.pdf:7", "--unlink", "05_Matchings.pdf"], setup: setup) { gist in
            SessionWrapUp(
                course: course, session: SessionCommandTests.id,
                ranges: [SessionMaterial(materialId: try material(gist, "Study/Problems.pdf"), firstPage: 7, lastPage: 7)],
                unlinked: [try material(gist, "05_Matchings.pdf")])
        }
        let gist = try Harness.fixtureCopy()
        for line in setup { _ = h.cli(line, gist: gist) }
        #expect(h.cli(["session", "wrap-up", "EC4207/10-28", "--unlink", "05_Matchings.pdf"], gist: gist).code == 0)
        let store = GISTStore(url: gist)
        let slides = try material(store, "05_Matchings.pdf")
        let f = try h.file(store)
        #expect(f.sessions.first { $0.id == SessionCommandTests.id }?.materials.isEmpty == true)
        #expect(f.materials.first { $0.id == slides }?.sessionIds.contains(SessionCommandTests.id) == false)
    }

    @Test func wrapUpDuringTheClassCountsOnlyAfterARecording() throws {
        let gist = try Harness.fixtureCopy()
        let id = UUID(uuidString: "A0000000-0000-4000-8000-0000000000F1")!
        #expect(h.cli(["session", "add", "EC4207", "--date", "2026-10-28 09:30", "--id", id.uuidString], gist: gist).code == 0)
        let wrapped = { try h.file(GISTStore(url: gist)).sessions.first { $0.id == id }?.isWrappedUp }
        try h.direct(SessionWrapUp(course: course, session: id, attendance: .set(.present)), gist: gist)
        #expect(try wrapped() == false)
        #expect(try !h.file(GISTStore(url: gist)).recordings.contains { $0.sessionId == id })
        try h.direct(SessionWrapUp(course: course, session: id, attendance: .set(.present), recorded: true), gist: gist)
        #expect(try wrapped() == true)
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
        #expect(
            h.cli(["material", "status", "ignored", "EC4207/Seating.pdf", "Guideline.pdf"], gist: gist).code
                == Exit.needsConfirmation.rawValue)
        try h.expectSame(["material", "status", "ignored", "EC4207/Seating.pdf", "Guideline.pdf", "--yes"], setup: [Self.track]) { gist in
            MaterialStatusSet(
                course: course, status: .ignored, materials: [try material(gist, "Seating.pdf"), try material(gist, "Guideline.pdf")])
        }
    }

    @Test func kindOfSeveralNeedsConfirmation() throws {
        let gist = try Harness.fixtureCopy()
        _ = h.cli(Self.track, gist: gist)
        #expect(
            h.cli(["material", "kind", "submission", "EC4207/Seating.pdf", "Guideline.pdf"], gist: gist).code
                == Exit.needsConfirmation.rawValue)
        try h.expectSame(["material", "kind", "submission", "EC4207/Seating.pdf", "Guideline.pdf", "--yes"], setup: [Self.track]) { gist in
            MaterialKindSet(
                course: course, kind: .submission, materials: [try material(gist, "Seating.pdf"), try material(gist, "Guideline.pdf")])
        }
    }

    @Test func relink() throws {
        try h.expectSame(["material", "relink", "EC4207/Seating.pdf", "Exams/Midterm/Guideline.pdf"], setup: [Self.track]) { gist in
            let store = try ActionContext(gist: gist, device: h.device).store(course)
            return MaterialRelink(
                course: course, material: try material(gist, "Seating.pdf"),
                file: store.url.appending(path: "Exams/Midterm/Guideline.pdf").path)
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
        #expect(
            h.cli(["material", "write", "EC4207/Problems.tex", "--file", file, "--expect", "00"], gist: gist).code == Exit.conflict.rawValue
        )
    }

    @Test func writeTakesTheHashShowReadsNow() throws {
        let gist = try Harness.fixtureCopy()
        _ = h.cli(Self.track, gist: gist)
        let tex = gist.appending(path: "2026-3/EC4207 그래프 이론/Study/Problems.tex")
        try "% 다른 기기에서 고침\n".write(to: tex, atomically: true, encoding: .utf8)
        let shown = try #require(
            try JSONSerialization.jsonObject(with: Data(h.cli(["material", "show", "EC4207/Problems.tex", "--json"], gist: gist).out.utf8))
                as? [String: Any])
        #expect(shown["text"] as? String == "% 다른 기기에서 고침\n" && shown["path"] as? String == "Study/Problems.tex")
        let hash = try #require(shown["contentHash"] as? String)
        let file = try scratch("Problems.tex", "x")
        #expect(h.cli(["material", "write", "EC4207/Problems.tex", "--file", file, "--expect", hash], gist: gist).code == 0)
        #expect(try String(contentsOf: tex, encoding: .utf8) == "x")
    }

    @Test func showReportsTheFormat() throws {
        let gist = try Harness.fixtureCopy()
        _ = h.cli(Self.track, gist: gist)
        let pdf = try #require(
            try JSONSerialization.jsonObject(with: Data(h.cli(["material", "show", "EC4207/Seating.pdf", "--json"], gist: gist).out.utf8))
                as? [String: Any])
        #expect(pdf["format"] as? String == "pdf" && pdf["text"] == nil)
        let tex = try #require(
            try JSONSerialization.jsonObject(with: Data(h.cli(["material", "show", "EC4207/Problems.tex", "--json"], gist: gist).out.utf8))
                as? [String: Any])
        #expect(tex["format"] as? String == "tex" && tex["text"] != nil)
        #expect(h.cli(["material", "show", "EC4207/Seating.pdf"], gist: gist).out.contains("pdf"))
    }

    @Test
    func buildTex() throws {
        let write = [
            "material", "write", "EC4207/Problems.tex", "--file",
            try scratch("Problems.tex", "\\documentclass{article}\n\\begin{document}\nHi\n\\end{document}\n"),
        ]
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
        try h.expectSame(
            ["material", "import", "EC4207", file, "--folder", "Lectures", "--session", "10-28"],
            setup: [Self.track, SessionCommandTests.add]
        ) { _ in
            MaterialImport(course: course, items: [ImportItem(file: file, folder: "Lectures", session: SessionCommandTests.id)])
        }
    }

    @Test func moveNeedsConfirmation() throws {
        let gist = try Harness.fixtureCopy()
        _ = h.cli(Self.track, gist: gist)
        #expect(
            h.cli(["material", "mv", "EC4207/Seating.pdf", "Exams/Midterm/자리.pdf"], gist: gist).code == Exit.needsConfirmation.rawValue)
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
        try h.expectSame(["cleanup", "apply", "--plan", try planFile(), "--backup", backup, "--yes"]) { _ in
            CleanupApply(moves: [Self.move])
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: backup).count == 1)
    }

    @Test func cleanupApplyLinksMovedFiles() throws {
        let gist = try Harness.fixtureCopy()
        _ = h.cli(Self.track, gist: gist)
        _ = h.cli(Self.addExam, gist: gist)
        let store = GISTStore(url: gist)
        let before = try material(store, "Exercises/Exercise 1.pdf")
        let ec = "2026-3/EC4207 그래프 이론"
        try h.direct(
            CleanupApply(moves: [
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
        try CleanupApply(moves: [PlannedMove(from: "\(ec)/Exercises/Exercise 1.pdf", to: "\(ec)/Study/Exercise 1.pdf", exam: "Quiz9")]).run(
            ctx)
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
        try h.expectSame([
            "note", "edit", "EC4207/09-08", "--old", "Matching", "--new", "매칭", "--old", "pairwise", "--new", "서로",
            "--append", "질문",
        ]) { _ in
            NoteEdit(
                course: course, note: "Notes/09-08(화) 매칭.md",
                replacements: [.init(old: "Matching", new: "매칭"), .init(old: "pairwise", new: "서로")], append: "질문")
        }
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(["note", "edit", "EC4207/09-08", "--old", "Matching"], gist: gist).code == Exit.usage.rawValue)
        #expect(h.cli(["note", "edit", "EC4207/09-08", "--old", "없는 글", "--new", "x"], gist: gist).code == Exit.conflict.rawValue)
    }

    func drop(_ gist: URL, _ name: String, _ text: String) throws {
        let store = try ActionContext(gist: GISTStore(url: gist), device: h.device, now: h.now).store(course)
        try text.write(to: store.url.appending(path: "Notes/\(name)"), atomically: true, encoding: .utf8)
    }

    @Test func noteAdopt() throws {
        try h.expectSame(["note", "adopt", "EC4207/바깥"], prepare: { try drop($0, "바깥.md", "# 바깥에서 만든 노트\n") }) { _ in
            NoteAdopt(course: course, note: "Notes/바깥.md")
        }
    }

    @Test
    func noteBuild() throws {
        let tex = "\\documentclass{article}\n\\begin{document}\nHi\n\\end{document}\n"
        let id = UUID()
        let prepare = { (gist: URL) in
            try NoteAdd(id: id, course: course, title: "증명", format: .tex).run(
                ActionContext(gist: GISTStore(url: gist), device: h.device, now: h.now))
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
        let setup = [
            SessionCommandTests.add, ["note", "mv", "EC4207/09-08", "2주차-1", "--yes"],
            ["note", "link", "EC4207/2주차-1", "--kind", "rough", "--session", "10-28"],
        ]
        try h.expectSame(["note", "retitle", "EC4207", "--yes"], setup: setup) { _ in
            NoteRetitleSessions(course: course)
        }
    }

    @Test func noteLink() throws {
        try h.expectSame(["note", "link", "EC4207/09-08", "--kind", "review", "--session", "10-28"], setup: [SessionCommandTests.add]) {
            _ in
            NoteLink(course: course, note: Self.noteID, kind: .review, session: SessionCommandTests.id)
        }
    }

    static let laterSession = UUID(uuidString: "A0000000-0000-4000-8000-000000000002")!
    static let reviewSetup = [
        SessionCommandTests.add, ["session", "add", "EC4207", "--date", "2026-10-30 10:30", "--id", laterSession.uuidString],
        ["note", "link", "EC4207/09-08", "--kind", "review", "--session", "10-28"],
    ]

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

    // MARK: Cards and problems

    static func addCards(_ file: String) -> [String] { ["card", "add", "EC4207", "--file", file] }

    @Test func cardAdd() throws {
        let file = try cardsFile()
        let cards = try JSONDecoder.folio.decode([StudyCard].self, from: Data(contentsOf: URL(filePath: file)))
        try h.expectSame(Self.addCards(file), setup: [Self.addUnit]) { _ in CardSave(course: course, cards: cards) }
    }

    @Test func cardRemove() throws {
        try h.expectSame(["card", "rm", "EC4207/매칭", "최대 매칭의 정의", "--yes"], setup: [Self.addUnit, Self.addCards(try cardsFile())]) {
            _ in CardRemove(course: course, unit: Self.unit, card: Self.card)
        }
    }

    @Test func cardFlip() throws {
        try h.expectSame(["card", "flip", "EC4207/매칭", "최대 매칭의 정의", "--unknown"], setup: [Self.addUnit, Self.addCards(try cardsFile())]) {
            _ in CardFlip(course: course, unit: Self.unit, card: Self.card, known: false)
        }
    }

    @Test func problemSetAdd() throws {
        try h.expectSame(Self.addSet) { _ in ProblemSetAdd(id: Self.set, course: course, title: "Exercise 1", numbers: ["1", "3a"]) }
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(Self.addSet, gist: gist).code == 0)
        let set = try #require(try h.file(GISTStore(url: gist)).problemSets.first { $0.id == Self.set })
        #expect(set.title == "Exercise 1" && set.source == .exercise && set.problems.map(\.number) == ["1", "3a"])
    }

    @Test func problemSetSet() throws {
        try h.expectSame(["problem-set", "set", "EC4207/Exercise 1", "--source", "past_exam", "--title", "2022 중간"], setup: [Self.addSet]) {
            _ in ProblemSetSet(course: course, set: Self.set, title: .set("2022 중간"), source: .set(.pastExam))
        }
    }

    @Test func problemSave() throws {
        let problems = [Problem(number: "4", text: "Hall 정리를 증명하시오.")]
        let file = try scratch("problems.json", String(bytes: try JSONEncoder.folio.encode(problems), encoding: .utf8) ?? "")
        try h.expectSame(["problem", "save", "EC4207/Exercise 1", "--file", file], setup: [Self.addSet]) { _ in
            ProblemSave(course: course, set: Self.set, problems: problems)
        }
    }

    static let attempt = uuid("A0000000-0000-4000-8000-0000000000F1")

    @Test func problemVerdict() throws {
        let solved: (URL) throws -> Void = { gist in
            try h.direct(ProblemSetAdd(id: Self.set, course: course, title: "Exercise 1", numbers: ["1"]), gist: gist)
            let problem = try #require(try h.file(GISTStore(url: gist)).problemSets.first?.problems.first?.id)
            try h.direct(ProblemSolve(id: Self.attempt, course: course, set: Self.set, problem: problem, verdict: .wrong), gist: gist)
        }
        try h.expectSame(["problem", "verdict", "EC4207", Self.attempt.uuidString, "correct"], prepare: solved) { _ in
            ProblemVerdict(course: course, attempt: Self.attempt.uuidString, verdict: .correct)
        }
    }

    @Test func materialViewed() throws {
        try h.expectSame(["material", "viewed", "EC4207/Lectures/05_Matchings.pdf", "7"], setup: [Self.track]) { gist in
            let material = try #require(try h.file(gist).materials.first { $0.path == "Lectures/05_Matchings.pdf" }?.id)
            return MaterialViewed(course: course, material: material, page: 7)
        }
    }

    static func examWithScope(_ gist: URL, _ h: Harness) throws {
        try h.direct(UnitAdd(id: unit, course: Harness.graphTheory, title: "매칭"), gist: gist)
        try h.direct(
            ExamAdd(id: exam, course: Harness.graphTheory, title: "Midterm", start: h.now.addingTimeInterval(7 * 86_400), scope: [unit]),
            gist: gist)
    }

    @Test func examPlanMake() throws {
        try h.expectSame(
            ["exam", "plan", "make", "EC4207/Midterm"], prepare: { try Self.examWithScope($0, h) },
            { _ in
                ExamPlanMake(course: course, exam: Self.exam)
            })
    }

    @Test func examPlanMove() throws {
        let item = uuid("A0000000-0000-4000-8000-0000000000F2")
        let planned: (URL) throws -> Void = { gist in
            try Self.examWithScope(gist, h)
            try h.direct(ExamPlanAdd(id: item, course: course, exam: Self.exam, title: "정리", day: ymd("2026-10-30")), gist: gist)
        }
        try h.expectSame(["exam", "plan", "move", "EC4207/Midterm", "정리", "--day", "2026-10-31"], prepare: planned) { _ in
            ExamPlanMove(course: course, exam: Self.exam, item: item, day: ymd("2026-10-31"))
        }
    }

    @Test func problemSetRemove() throws {
        try h.expectSame(["problem-set", "rm", "EC4207/Exercise 1", "--yes"], setup: [Self.addSet]) { _ in
            ProblemSetRemove(course: course, set: Self.set)
        }
    }

    static let midterm = "Inherited/소순범/2024 Midterm.pdf"

    static let midtermID = uuid("A0000000-0000-4000-8000-0000000000F3")

    // 초안 파일 이름이 자료 ID이므로, 두 사본이 같은 파일을 쓰게 등록한 자료의 ID를 정해 둔다.
    func tracked(_ gist: URL) throws {
        try h.direct(MaterialTrack(course: course, assignments: false), gist: gist)
        let ctx = ActionContext(gist: GISTStore(url: gist), device: h.device, now: h.now)
        try ctx.edit(course) { file in
            if let i = file.materials.firstIndex(where: { $0.path == Self.midterm }) { file.materials[i].id = Self.midtermID }
        }
    }

    func proposed(_ gist: URL) throws {
        try tracked(gist)
        try h.direct(
            ProblemSetPropose(course: course, material: Self.midtermID, problems: [Problem(number: "1", text: "홀의 정리를 쓰시오.")]),
            gist: gist)
    }

    @Test func problemSetPropose() throws {
        let problems = [Problem(number: "1", page: 1, text: "홀의 정리를 쓰시오.")]
        let file = try scratch("drafted.json", String(bytes: try JSONEncoder.folio.encode(problems), encoding: .utf8) ?? "")
        try h.expectSame(
            ["problem-set", "propose", "EC4207/2024 Midterm.pdf", "--file", file], prepare: tracked
        ) { _ in
            ProblemSetPropose(course: course, material: Self.midtermID, problems: problems)
        }
    }

    @Test func problemSetAccept() throws {
        try h.expectSame(["problem-set", "accept", "EC4207/2024 Midterm.pdf", "--title", "2024 중간"], prepare: proposed) { _ in
            ProblemSetAccept(course: course, material: Self.midtermID, title: "2024 중간")
        }
    }

    @Test func problemSetDiscard() throws {
        try h.expectSame(["problem-set", "discard", "EC4207/2024 Midterm.pdf", "--yes"], prepare: proposed) { _ in
            ProblemSetDiscard(course: course, material: Self.midtermID)
        }
    }

    @Test func problemSetLink() throws {
        try h.expectSame(["problem-set", "link", "EC4207/Exercise 1", "3a", "매칭"], setup: [Self.addUnit, Self.addSet]) { _ in
            ProblemLinkUnit(course: course, set: Self.set, number: "3a", unit: Self.unit, linked: true)
        }
    }

    func problemID(_ gist: GISTStore, _ number: String) throws -> UUID {
        try #require(try h.file(gist).problemSets.first { $0.id == Self.set }?.problems.first { $0.number == number }?.id)
    }

    @Test func problemSolve() throws {
        try h.expectSame(["problem", "solve", "EC4207/Exercise 1", "3a", "wrong", "--reason", "concept"], setup: [Self.addSet]) { gist in
            ProblemSolve(course: course, set: Self.set, problem: try problemID(gist, "3a"), verdict: .wrong, reason: .concept)
        }
    }

    @Test func problemRemove() throws {
        try h.expectSame(["problem", "rm", "EC4207/Exercise 1", "3a", "--yes"], setup: [Self.addSet]) { gist in
            ProblemRemove(course: course, set: Self.set, problem: try problemID(gist, "3a"))
        }
    }

    @Test func unitDone() throws {
        try h.expectSame(["unit", "done", "EC4207/매칭"], setup: [Self.addUnit]) { _ in UnitDone(course: course, unit: Self.unit) }
    }
}

private func ymd(_ text: String) -> LocalDate {
    guard let day = LocalDate(text) else { preconditionFailure(text) }
    return day
}

private func uuid(_ text: String) -> UUID {
    guard let id = UUID(uuidString: text) else { preconditionFailure(text) }
    return id
}
