@testable import FolioCLI
import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

struct UnitExamAssignmentTests {
    let h = Harness()
    let course = Harness.graphTheory

    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "B0000000-0000-4000-8000-%012d", n))! }
    static let (session, tree, matching, exam, item, note, hw) = (id(1), id(2), id(3), id(4), id(5), id(6), id(7))

    static let addSession = ["session", "add", "EC4207", "--date", "2026-10-28 10:30", "--id", session.uuidString]
    static let addTree = ["unit", "add", "EC4207", "트리", "--id", tree.uuidString]
    static let addMatching = ["unit", "add", "EC4207", "매칭", "--id", matching.uuidString]
    static let addExam = ["exam", "add", "EC4207", "중간고사", "--kind", "midterm", "--start", "2026-10-29 10:00", "--id", exam.uuidString]
    static let addItem = ["exam", "plan", "add", "EC4207/중간고사", "트리 복습", "--day", "2026-10-27", "--id", item.uuidString]
    static let addHW = ["assignment", "add", "EC4207", "HW 3", "--due", "2026-11-04 23:59", "--id", hw.uuidString]

    func date(_ s: String) -> Date { DateArg(argument: s)!.date }

    // MARK: Units

    @Test func unitAdd() throws {
        try h.expectSame(Self.addTree) { _ in UnitAdd(id: Self.tree, course: course, title: "트리") }
    }

    @Test func unitRemove() throws {
        try h.expectSame(["unit", "rm", "EC4207/트리", "--yes"], setup: [Self.addTree]) { _ in UnitRemove(course: course, unit: Self.tree) }
    }

    @Test func unitSet() throws {
        try h.expectSame(["unit", "set", "EC4207/트리", "--title", "숲"], setup: [Self.addTree]) { _ in UnitSet(course: course, unit: Self.tree, title: "숲") }
    }

    @Test func unitMove() throws {
        try h.expectSame(["unit", "move", "EC4207/매칭", "--parent", "트리"], setup: [Self.addTree, Self.addMatching]) { _ in
            UnitMove(course: course, unit: Self.matching, target: .parent(Self.tree))
        }
    }

    @Test func unitLink() throws {
        try h.expectSame(["unit", "link", "EC4207/트리", "9주차-1"], setup: [Self.addSession, Self.addTree]) { _ in
            UnitLink(course: course, unit: Self.tree, sessions: [Self.session])
        }
    }

    // MARK: Exams

    @Test func examAdd() throws {
        try h.expectSame(Self.addExam) { _ in
            ExamAdd(id: Self.exam, course: course, title: "중간고사", kind: .midterm, start: date("2026-10-29 10:00"))
        }
    }

    @Test func examSet() throws {
        try h.expectSame(["exam", "set", "EC4207/중간고사", "--location", "B101"], setup: [Self.addExam]) { _ in
            ExamSet(course: course, exam: Self.exam, location: .set("B101"))
        }
        try h.expectSame(["exam", "set", "EC4207/중간고사", "--scope", "트리", "--memo", "증명 위주"], setup: [Self.addTree, Self.addExam]) { _ in
            ExamSet(course: course, exam: Self.exam, scope: .set([Self.tree]), memo: .set("증명 위주"))
        }
    }

    @Test func examRemove() throws {
        try h.expectSame(["exam", "rm", "EC4207/중간고사", "--yes"], setup: [Self.addExam]) { _ in ExamRemove(course: course, exam: Self.exam) }
    }

    @Test func examScope() throws {
        try h.expectSame(["exam", "scope", "EC4207/중간고사", "--unit", "트리"], setup: [Self.addTree, Self.addExam]) { _ in
            ExamScope(course: course, exam: Self.exam, unit: Self.tree, included: true)
        }
    }

    @Test func examScopeTaught() throws {
        let setup = [Self.addSession, Self.addTree, ["unit", "link", "EC4207/트리", "9주차-1"], Self.addExam]
        try h.expectSame(["exam", "scope", "EC4207/중간고사", "--taught"], setup: setup) { _ in ExamScopeTaught(course: course, exam: Self.exam) }
        let gist = try Harness.fixtureCopy()
        for line in setup + [["exam", "scope", "EC4207/중간고사", "--taught"]] { #expect(h.cli(line, gist: gist).code == 0) }
        #expect(try h.file(GISTStore(url: gist)).exams[0].scopeUnitIds == [Self.tree])
    }

    @Test func examPlan() throws {
        try h.expectSame(Self.addItem, setup: [Self.addExam]) { _ in
            ExamPlanAdd(id: Self.item, course: course, exam: Self.exam, title: "트리 복습", day: LocalDate("2026-10-27")!)
        }
        try h.expectSame(["exam", "plan", "rm", "EC4207/중간고사", "트리 복습", "--yes"], setup: [Self.addExam, Self.addItem]) { _ in
            ExamPlanRemove(course: course, exam: Self.exam, item: Self.item)
        }
    }

    @Test func examPlanCheck() throws {
        try h.expectSame(["exam", "plan-check", "EC4207/중간고사", "트리 복습"], setup: [Self.addExam, Self.addItem]) { _ in
            ExamPlanCheck(course: course, item: Self.item, done: true)
        }
    }

    @Test func examSummary() throws {
        try h.expectSame(["exam", "summary", "EC4207/중간고사", "--id", Self.note.uuidString], setup: [Self.addExam]) { _ in
            ExamSummary(note: Self.note, course: course, exam: Self.exam)
        }
    }

    // MARK: Assignments

    @Test func assignmentAdd() throws {
        try h.expectSame(Self.addHW) { _ in AssignmentAdd(id: Self.hw, course: course, title: "HW 3", due: date("2026-11-04 23:59")) }
    }

    @Test func assignmentSet() throws {
        try h.expectSame(["assignment", "set", "EC4207/HW 3", "--memo", "3번 질문함"], setup: [Self.addHW]) { _ in
            AssignmentSave(course: course, assignment: Self.hw, title: "HW 3", due: date("2026-11-04 23:59"), status: .todo, repeats: nil,
                           componentId: nil, componentGroup: nil, memo: "3번 질문함", components: [], scores: [])
        }
    }

    @Test func assignmentStatus() throws {
        try h.expectSame(["assignment", "status", "EC4207/HW 3", "submitted"], setup: [Self.addHW]) { _ in
            AssignmentStatusSet(course: course, assignment: Self.hw, status: .submitted)
        }
    }

    @Test func assignmentRemove() throws {
        try h.expectSame(["assignment", "rm", "EC4207/HW 3", "--yes"], setup: [Self.addHW]) { _ in AssignmentRemove(course: course, assignment: Self.hw) }
    }

    @Test func removalsNeedConfirmationOffTerminal() throws {
        let gist = try Harness.fixtureCopy()
        #expect(h.cli(Self.addTree, gist: gist).code == 0)
        #expect(h.cli(["unit", "rm", "EC4207/트리"], gist: gist).code == Exit.needsConfirmation.rawValue)
    }

    @Test func treeLines() {
        #expect([0, 1, 2, 1, 0].indices.map { treePrefix([0, 1, 2, 1, 0], at: $0) } == ["", "├─ ", "│  └─ ", "└─ ", ""])
    }
}
