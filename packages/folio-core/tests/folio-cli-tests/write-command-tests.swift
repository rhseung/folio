@testable import FolioCLI
import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

struct WriteCommandTests {
    let h = Harness()
    let gt = Harness.graphTheory
    let grades = GradesSetupTests()
    typealias G = GradesSetupTests
    typealias U = UnitExamAssignmentTests

    // MARK: Set options

    @Test func policyCapsCutoffsAndClearing() throws {
        try h.expectSame(["component", "policy", "EC4207", "--cap", "6:A+", "--cutoff", "A+:95", "--lates-per-absence", "none"],
                         setup: [["catalog", "set", "--file", try grades.catalogFile()], ["component", "policy", "EC4207", "--lates-per-absence", "3"]]) { _ in
            var p = GradePolicy()
            p.attendanceCap = [AttendanceCap(absences: 6, maxGrade: G.grade)]
            p.cutoffs = [GradeCutoff(grade: G.grade, minScore: 95)]
            return PolicySet(course: gt, policy: p)
        }
    }

    @Test func requirementPrograms() throws {
        try h.expectSame(["requirement", "set", "--program", "major:EC"], setup: [["catalog", "set", "--file", try grades.catalogFile()]]) { _ in
            GraduationSet(rule: GraduationRule(programs: [StudentProgram(codeId: G.code, kind: .major)]))
        }
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(["requirement", "set", "--program", "major"], gist: gist).code == 2)
    }

    @Test func semesterClearsAWeek() throws {
        try h.expectSame(["semester", "set", "2026-3", "--midterm-week", "none"], setup: [["semester", "set", "2026-3", "--midterm-week", "8"]]) { _ in
            SemesterSet(semester: G.fall, midtermWeek: .set(nil))
        }
    }

    @Test func settingsField() throws {
        try h.expectSame(["settings", "set", "review.intervals", "[1, 2, 4]"]) { gist in
            var s = try ActionContext(gist: gist, device: h.device).settings()
            s.review.intervals = [1, 2, 4]
            return SettingsSet(settings: s)
        }
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(["settings", "set", "review.intervalz", "[1]"], gist: gist).code == 2)
        #expect(h.cli(["settings", "set", "dayBoundaryMinutes", "새벽"], gist: gist).code == 2)
    }

    @Test func sidebarCourseOrder() throws {
        let order = [UUID(uuidString: "C0000000-0000-4000-8000-000000000003")!, UUID(uuidString: "C0000000-0000-4000-8000-000000000002")!]
        try h.expectSame(["settings", "set", "sidebar.courses", #"["\#(order[0])", "\#(order[1])"]"#]) { gist in
            var s = try ActionContext(gist: gist, device: h.device).settings()
            s.sidebar.courses = order
            return SettingsSet(settings: s)
        }
    }

    @Test func assignmentScoreAndClearedDue() throws {
        try h.expectSame(["assignment", "set", "EC4207/HW 3", "--component", "과제", "--score", "9/10", "--due", "none"],
                         setup: [G.addComponent, U.addHW]) { _ in
            AssignmentSave(course: gt, assignment: U.hw, title: "HW 3", due: nil, status: .todo, repeats: nil, componentId: G.component,
                           componentGroup: nil, memo: "", components: [G.component], scores: [.init(component: G.component, score: 9, max: 10)])
        }
    }

    @Test func assignmentGroupScoresEachComponent() throws {
        let lab = ["component", "add", "EC4207", "재료", "--weight", "10", "--group", "실험", "--id", G.component.uuidString]
        let report = ["component", "add", "EC4207", "고찰", "--weight", "10", "--group", "실험", "--id", G.quiz.uuidString]
        try h.expectSame(["assignment", "set", "EC4207/HW 3", "--group", "실험", "--score", "재료:8/10", "--repeats", "weekly"],
                         setup: [lab, report, U.addHW]) { _ in
            AssignmentSave(course: gt, assignment: U.hw, title: "HW 3", due: U().date("2026-11-04 23:59"), status: .todo, repeats: .weekly,
                           componentId: nil, componentGroup: "실험", memo: "", components: [G.component, G.quiz],
                           scores: [.init(component: G.component, score: 8, max: 10)])
        }
        let gist = try Harness.fixtureCopy()
        for line in [lab, report, U.addHW] { _ = h.cli(line, gist: gist) }
        #expect(h.cli(["assignment", "set", "EC4207/HW 3", "--group", "실험", "--score", "8/10"], gist: gist).code == 2)
        #expect(h.cli(["assignment", "set", "EC4207/HW 3", "--group", "없는 묶음"], gist: gist).code == 3)
    }

    @Test func examClearsTheStart() throws {
        try h.expectSame(["exam", "set", "EC4207/중간고사", "--start", "none"], setup: [U.addExam]) { _ in
            ExamSet(course: gt, exam: U.exam, start: .set(nil))
        }
    }

    // MARK: Note conflicts

    @Test func noteWriteChecksTheHash() throws {
        let gist = try Harness.fixtureCopy()
        let shown = h.cli(["note", "show", "EC4207/2주차-1", "--json"], gist: gist)
        let hash = try #require((try JSONSerialization.jsonObject(with: Data(shown.out.utf8)) as? [String: Any])?["hash"] as? String)
        let file = FileManager.default.temporaryDirectory.appending(path: "note-\(UUID().uuidString).md")
        try "# 새 내용\n".write(to: file, atomically: true, encoding: .utf8)

        let note = gist.appending(path: "2026-3/EC4207 그래프 이론/Notes/2주차-1.md")
        let before = try String(contentsOf: note, encoding: .utf8)
        let stale = h.cli(["note", "write", "EC4207/2주차-1", "--file", file.path, "--expect", String(repeating: "0", count: 64)], gist: gist)
        #expect(stale.code == 6)
        #expect(try String(contentsOf: note, encoding: .utf8) == before)

        #expect(h.cli(["note", "write", "EC4207/2주차-1", "--file", file.path, "--expect", hash], gist: gist).code == 0)
        #expect(try String(contentsOf: note, encoding: .utf8) == "# 새 내용\n")
    }

    // MARK: Output

    @Test func changedFieldsShowBeforeAndAfter() throws {
        let gist = try Harness.fixtureCopy()
        _ = h.cli(U.addExam, gist: gist)
        let r = h.cli(["exam", "set", "EC4207/중간고사", "--location", "B101", "--json"], gist: gist)
        let result = try JSONDecoder().decode(WriteResultProbe.self, from: Data(r.out.utf8))
        let fields = result.changes.compactMap(\.fields).flatMap { $0 }
        #expect(fields.contains { $0.name == "location" && $0.before == .string("") && $0.after == .string("B101") })
        #expect(!fields.contains { $0.name == "updatedAt" })
        #expect(h.cli(["exam", "set", "EC4207/중간고사", "--location", "B203"], gist: gist).out.contains("location: B101 → B203"))
    }

    @Test func severalActionsListEachChangeOnce() throws {
        let gist = try Harness.fixtureCopy()
        for line in [U.addTree, ["session", "add", "EC4207", "--date", "2026-10-26 10:30"], ["session", "add", "EC4207", "--date", "2026-10-28 10:30"]] {
            _ = h.cli(line, gist: gist)
        }
        let r = h.cli(["unit", "link", "EC4207/트리", "9주차-1", "9주차-2", "--json"], gist: gist)
        #expect(r.code == 0, "\(r.err)")
        let changes = try JSONDecoder().decode(WriteResultProbe.self, from: Data(r.out.utf8)).changes
        let keys = changes.map { "\($0.path)|\($0.item ?? "")" }
        #expect(keys.count == Set(keys).count)
    }

    @Test func coalescedKeepsFirstBeforeAndLastAfter() {
        let a = FolioActions.Change(.changed, "c.json", item: "units/1", fields: [.init(name: "title", before: .string("A"), after: .string("B"))])
        let b = FolioActions.Change(.changed, "c.json", item: "units/1", fields: [.init(name: "title", before: .string("B"), after: .string("C"))])
        let added = FolioActions.Change(.added, "c.json", item: "units/2")
        let merged = [a, added, b, FolioActions.Change(.changed, "c.json", item: "units/2")].coalesced()
        #expect(merged.count == 2)
        #expect(merged[0].fields == [.init(name: "title", before: .string("A"), after: .string("C"))])
        #expect(merged[1].kind == .added)
    }

    // MARK: Omitted items

    @Test func anOmittedItemIsAUsageErrorWithoutATerminal() throws {
        let gist = try Harness.fixtureCopy()
        for line in [U.addExam, U.addTree] { _ = h.cli(line, gist: gist) }
        for args in [["exam", "show"], ["exam", "show", "EC4207"], ["exam", "scope", "EC4207/중간고사"], ["unit", "link", "EC4207/트리"]] {
            let r = h.cli(args, gist: gist)
            #expect(r.code == 2, "\(args): \(r.err)")
        }
        // A bare item still points at the missing course rather than guessing one.
        #expect(h.cli(["exam", "show", "중간고사"], gist: gist).code == 2)
    }
}

struct WriteResultProbe: Decodable {
    var changes: [FolioActions.Change]
}
