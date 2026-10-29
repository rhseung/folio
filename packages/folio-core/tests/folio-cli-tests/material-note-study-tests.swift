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
        try h.expectSame(["material", "link", "EC4207/05_Matchings.pdf", "9주차-1", "--pages", "3-12"], setup: [Self.track, SessionCommandTests.add]) { gist in
            MaterialLinkSession(course: course, material: try material(gist, "05_Matchings.pdf"), session: SessionCommandTests.id, firstPage: 3, lastPage: 12)
        }
    }

    @Test func linkUnit() throws {
        try h.expectSame(["material", "link-unit", "EC4207/05_Matchings.pdf", "매칭"], setup: [Self.track, Self.addUnit]) { gist in
            MaterialLinkUnit(course: course, material: try material(gist, "05_Matchings.pdf"), unit: Self.unit, linked: true)
        }
    }

    @Test func statusOfSeveralNeedsConfirmation() throws {
        let gist = try Harness.fixtureCopy()
        _ = h.cli(Self.track, gist: gist)
        #expect(h.cli(["material", "status", "ignored", "EC4207/Seating.pdf", "Guideline.pdf"], gist: gist).code == Exit.needsConfirmation.rawValue)
        try h.expectSame(["material", "status", "ignored", "EC4207/Seating.pdf", "Guideline.pdf", "--yes"], setup: [Self.track]) { gist in
            MaterialStatusSet(course: course, materials: [try material(gist, "Seating.pdf"), try material(gist, "Guideline.pdf")], status: .ignored)
        }
    }

    @Test func relink() throws {
        try h.expectSame(["material", "relink", "EC4207/Seating.pdf", "Exams/Midterm/Guideline.pdf"], setup: [Self.track]) { gist in
            let store = try ActionContext(gist: gist, device: h.device).store(course)
            return MaterialRelink(course: course, material: try material(gist, "Seating.pdf"), file: store.url.appending(path: "Exams/Midterm/Guideline.pdf").path)
        }
    }

    @Test func untrack() throws {
        try h.expectSame(["material", "untrack", "EC4207/Seating.pdf"], setup: [Self.track]) { gist in
            MaterialUntrack(course: course, material: try material(gist, "Seating.pdf"))
        }
    }

    @Test func importCopiesAndLinks() throws {
        let file = try scratch("06_Coloring.pdf", "pdf")
        try h.expectSame(["material", "import", "EC4207", file, "--folder", "Lectures", "--week", "6", "--session", "9주차-1"],
                         setup: [Self.track, SessionCommandTests.add]) { _ in
            MaterialImport(course: course, files: [file], folder: "Lectures", week: 6, session: SessionCommandTests.id)
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
            NoteAdd(id: id, course: course, title: "매칭 정리", kind: .topic)
        }
    }

    @Test func noteWrite() throws {
        let text = "---\nid: \(Self.noteID.uuidString.lowercased())\nkind: rough\n---\n\n# 2주차-1\n\n고쳐 씀\n"
        try h.expectSame(["note", "write", "EC4207/2주차-1", "--file", try scratch("note.md", text)]) { _ in
            NoteWrite(course: course, note: "Notes/2주차-1.md", text: text)
        }
    }

    @Test func noteAdopt() throws {
        let plain = try scratch("plain.md", "# 바깥에서 만든 노트\n")
        try h.expectSame(["note", "adopt", "EC4207/2주차-1"], setup: [["note", "write", "EC4207/2주차-1", "--file", plain]]) { _ in
            NoteAdopt(course: course, note: "Notes/2주차-1.md")
        }
    }

    @Test func noteLink() throws {
        try h.expectSame(["note", "link", "EC4207/2주차-1", "--kind", "review", "--session", "9주차-1"], setup: [SessionCommandTests.add]) { _ in
            NoteLink(course: course, note: Self.noteID, kind: .review, session: SessionCommandTests.id)
        }
    }

    @Test func noteRemove() throws {
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(["note", "rm", "EC4207/2주차-1"], gist: gist).code == Exit.needsConfirmation.rawValue)
        try h.expectSame(["note", "rm", "EC4207/2주차-1", "--yes"]) { _ in NoteRemove(course: course, note: "Notes/2주차-1.md") }
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
}
