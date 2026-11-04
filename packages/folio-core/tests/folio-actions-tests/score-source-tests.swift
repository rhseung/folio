import FolioActions
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

/// A score means the same whether it was put in on the grades page or in the assignment sheet.
struct ScoreSourceTests {
    let course = ActionTests.graphTheory
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let gist: GISTStore
    let homework = UUID(), lab = UUID(), assignment = UUID(), exam = UUID()

    init() throws {
        gist = GISTStore(url: try Fixture.standard.copyToTemp())
        try run(ComponentAdd(id: homework, course: course, name: "숙제", weight: 20))
        try run(ComponentAdd(id: lab, course: course, name: "실험", weight: 20))
        try run(AssignmentAdd(id: assignment, course: course, title: "HW 3"))
        try run(ExamAdd(id: exam, course: course, title: "소테스트", component: homework))
    }

    func run(_ action: some Action) throws {
        try action.run(ActionContext(gist: gist, device: device, now: now))
    }

    func file() throws -> CourseFile { try ActionContext(gist: gist, device: device).file(course) }

    func save(title: String = "HW 3", status: AssignmentStatus = .submitted, component: UUID?, shown: [UUID], scores: [AssignmentSave.Score]) throws {
        try run(AssignmentSave(course: course, assignment: assignment, title: title, due: nil, status: status, repeats: nil, componentId: component,
                               componentGroup: nil, memo: "", components: shown, scores: scores))
    }

    func score(in component: UUID) throws -> ScoreEntry? { try file().scores.first { $0.assignmentId == assignment && $0.componentId == component } }

    @Test func aScoreAddedOnTheGradesPageGradesItsAssignment() throws {
        try run(AssignmentStatusSet(course: course, assignment: assignment, status: .submitted))
        try run(ScoreAdd(course: course, component: homework, title: "HW3", score: 9, max: 10, assignment: assignment))
        #expect(try file().assignments.first { $0.id == assignment }?.status == .graded)
    }

    @Test func editingALinkedScoreKeepsAStatusSetByHand() throws {
        let id = UUID()
        try run(ScoreAdd(id: id, course: course, component: homework, score: 9, max: 10, assignment: assignment))
        try run(AssignmentStatusSet(course: course, assignment: assignment, status: .submitted))
        try run(ScoreSet(course: course, score: id, value: .set(10), assignment: .set(assignment)))
        #expect(try file().assignments.first { $0.id == assignment }?.status == .submitted)
    }

    @Test func linkingAnExistingScoreGradesTheAssignment() throws {
        let id = UUID()
        try run(ScoreAdd(id: id, course: course, component: homework, score: 9, max: 10))
        try run(ScoreSet(course: course, score: id, assignment: .set(assignment)))
        #expect(try file().assignments.first { $0.id == assignment }?.status == .graded)
    }

    @Test func aScoreStandsForOneAssignmentOrOneExam() throws {
        #expect(throws: ActionError.self) {
            try run(ScoreAdd(course: course, component: homework, score: 9, max: 10, exam: exam, assignment: assignment))
        }
    }

    @Test func anAssignmentHasOneScorePerComponent() throws {
        try run(ScoreAdd(course: course, component: homework, score: 9, max: 10, assignment: assignment))
        #expect(throws: ActionError.self) { try run(ScoreAdd(course: course, component: homework, score: 8, max: 10, assignment: assignment)) }
        try run(ScoreAdd(course: course, component: lab, score: 8, max: 10, assignment: assignment))
        #expect(try file().scores.count { $0.assignmentId == assignment } == 2)
    }

    @Test func savingTheSheetKeepsAScoreMovedToAnotherComponent() throws {
        try save(component: homework, shown: [homework], scores: [.init(component: homework, score: 9, max: 10)])
        let id = try #require(try score(in: homework)).id
        try run(ScoreSet(course: course, score: id, component: .set(lab), title: .set("HW3 재채점")))

        // The sheet still targets 숙제 and shows its field empty; only the due date changed.
        try save(component: homework, shown: [homework], scores: [])
        let moved = try #require(try score(in: lab))
        #expect(moved.id == id && moved.title == "HW3 재채점" && moved.score == 9)
        #expect(try file().assignments.first { $0.id == assignment }?.status == .graded)
    }

    @Test func savingTheSheetKeepsATitleNamedOnTheGradesPage() throws {
        try save(component: homework, shown: [homework], scores: [.init(component: homework, score: 9, max: 10)])
        let id = try #require(try score(in: homework)).id
        try run(ScoreSet(course: course, score: id, title: .set("3번 숙제")))
        try save(title: "HW 3 (보충)", component: homework, shown: [homework], scores: [.init(component: homework, score: 10, max: 10)])
        let s = try #require(try score(in: homework))
        #expect(s.title == "3번 숙제" && s.score == 10)
    }

    @Test func aTitleThatFollowedTheAssignmentFollowsItsRename() throws {
        try save(component: homework, shown: [homework], scores: [.init(component: homework, score: 9, max: 10)])
        try save(title: "HW 3 (보충)", component: homework, shown: [homework], scores: [.init(component: homework, score: 9, max: 10)])
        #expect(try score(in: homework)?.title == "HW 3 (보충)")
    }

    @Test func clearingAShownFieldRemovesItsScore() throws {
        try save(component: homework, shown: [homework], scores: [.init(component: homework, score: 9, max: 10)])
        try save(component: homework, shown: [homework], scores: [])
        #expect(try score(in: homework) == nil)
    }

    @Test func sourcesCountingTowardTheComponentComeFirst() throws {
        try run(AssignmentAdd(course: course, title: "Lab 1"))
        try save(component: homework, shown: [], scores: [])
        let f = try file()
        let sources = f.scoreSources(for: homework)
        #expect(sources.first == .assignment(assignment))
        #expect(sources.firstIndex(of: .exam(exam)).map { i in sources[i...].allSatisfy { if case .exam = $0 { true } else { false } } } == true)
        #expect(f.counts(.exam(exam), toward: homework) && !f.counts(.exam(exam), toward: lab))
    }
}
