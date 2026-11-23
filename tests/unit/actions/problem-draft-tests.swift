import FolioActions
import FolioCore
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

struct ProblemDraftTests {
    static let graphTheory = ActionTests.graphTheory
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let gist: GISTStore

    init() throws {
        gist = GISTStore(url: try Fixture.standard.copyToTemp())
        try run(MaterialTrack(course: Self.graphTheory, assignments: false))
    }

    @discardableResult
    func run(_ action: some Action) throws -> ActionContext {
        let ctx = ActionContext(gist: gist, device: device, now: now)
        try action.run(ctx)
        return ctx
    }

    func file() throws -> CourseFile { try ActionContext(gist: gist, device: device).file(Self.graphTheory) }
    func drafts() throws -> [StudyDraft] { try ActionContext(gist: gist, device: device).store(Self.graphTheory).drafts().map(\.model) }

    func material(_ path: String) throws -> Material {
        try #require(try file().materials.first { $0.path == path })
    }

    let problems = [
        Problem(number: "1", page: 1, text: "$K_{3,3}$는 평면 그래프인가?", format: .trueFalse, options: Problem.trueFalseOptions),
        Problem(number: "2a", parent: "2", points: 5, page: 2, text: "Hall 정리를 쓰시오."),
        Problem(number: "2b", parent: "2", points: 5, page: 2, text: "증명하시오."),
    ]

    @Test func aProposalWaitsInDraftsWithTheSolutionFoundByName() throws {
        let sheet = try material("Inherited/소순범/2024 Midterm.pdf")
        let solution = try material("Inherited/소순범/2024 Midterm Solution.pdf")
        let before = try file()
        let ctx = try run(ProblemSetPropose(course: Self.graphTheory, material: sheet.id, problems: problems))
        #expect(try file().problemSets == before.problemSets)
        #expect(ctx.changes.contains { $0.touchesStudy })

        let draft = try #require(try drafts().first)
        #expect(draft.kind == .problems && draft.materialId == sheet.id && draft.title == "2024 Midterm" && ctx.made == draft.id)
        #expect(draft.problems.map(\.number) == ["1", "2a", "2b"] && draft.solutionMaterialId == solution.id)
        #expect(draft.proposal.command == "problem-set add" && draft.proposal.input["source"] == "past_exam")

        // 같은 자료를 다시 뽑으면 앞의 제안을 바꾼다.
        try run(ProblemSetPropose(course: Self.graphTheory, material: sheet.id, title: "2024 중간", problems: Array(problems.prefix(1))))
        #expect(try drafts().map(\.problems.count) == [1])
        #expect(try drafts().first?.proposal.input["title"] == "2024 중간")

        #expect(throws: ActionError.self) { try run(ProblemSetPropose(course: Self.graphTheory, material: sheet.id, problems: [])) }
        #expect(throws: ActionError.self) { try run(ProblemSetPropose(course: Self.graphTheory, material: UUID(), problems: problems)) }
    }

    @Test func acceptingMakesOneSetAndClearsTheDraftEvenTwice() throws {
        let sheet = try material("Inherited/소순범/2024 Midterm.pdf")
        try run(ProblemSetPropose(course: Self.graphTheory, material: sheet.id, problems: problems))
        let draft = try #require(try drafts().first)
        let kept = Array(draft.problems.dropFirst())
        let ctx = try run(ProblemSetAccept(course: Self.graphTheory, material: sheet.id, title: "중간 2024", problems: kept))
        #expect(ctx.changes.contains { $0.touchesStudy })

        let set = try #require(try file().problemSets.first { $0.materialId == sheet.id })
        #expect(set.title == "중간 2024" && set.source == .pastExam && set.problems.map(\.number) == ["2a", "2b"])
        let solution = try material("Inherited/소순범/2024 Midterm Solution.pdf")
        #expect(set.solutionMaterialId == solution.id)
        #expect(try file().hasApplied(try #require(draft.proposal.id)))
        #expect(try drafts().isEmpty)

        // 다른 기기가 같은 초안을 받으면 묶음을 하나 더 만들지 않고 초안만 치운다.
        try ActionContext(gist: gist, device: device).store(Self.graphTheory).save(StoredDocument(new: draft))
        try run(ProblemSetAccept(course: Self.graphTheory, material: sheet.id))
        #expect(try file().problemSets.filter { $0.materialId == sheet.id }.count == 1)
        #expect(try drafts().isEmpty)

        #expect(throws: ActionError.self) { try run(ProblemSetAccept(course: Self.graphTheory, material: sheet.id)) }
    }

    @Test func theStemAndItsFigureTravelWithTheProposalAndLeaveWithTheirSubProblems() throws {
        let sheet = try material("Assignments/HW03/26h3.pdf")
        let graph = try #require(ProblemRegion(page: 1, x: 0.1, y: 0.4, width: 0.5, height: 0.2))
        let stem = ProblemGroup(number: "2", page: 2, text: "Let $G$ be the graph below.")
        let drawn = problems.map { p in
            var p = p; if p.parent == "2" { p.figures = [graph] }; return p
        }
        try run(ProblemSetPropose(course: Self.graphTheory, material: sheet.id, problems: drawn, groups: [stem]))
        let draft = try #require(try drafts().first)
        // 두 소문제가 함께 보는 그림은 지문으로 간다.
        #expect(draft.groups.map(\.number) == ["2"] && draft.groups[0].figures == [graph])
        #expect(draft.problems.allSatisfy { $0.figures.isEmpty })

        try run(ProblemSetAccept(course: Self.graphTheory, material: sheet.id))
        let set = try #require(try file().problemSets.first { $0.materialId == sheet.id })
        let tree = ProblemTree(set)
        #expect(tree.stems(of: set.problems[1].id).map(\.text) == [stem.text] && tree.stems(of: set.problems[0].id).isEmpty)

        // 소문제를 모두 빼고 받으면 지문도 남지 않는다.
        let other = try material("Exercises/Exercise 1.pdf")
        try run(ProblemSetPropose(course: Self.graphTheory, material: other.id, problems: drawn, groups: [stem]))
        try run(ProblemSetAccept(course: Self.graphTheory, material: other.id, problems: Array(drawn.prefix(1))))
        let kept = try #require(try file().problemSets.first { $0.materialId == other.id })
        #expect(kept.groups.isEmpty)
    }

    @Test func discardingLeavesNothingInTheCourse() throws {
        let sheet = try material("Exercises/Exercise 1.pdf")
        try run(ProblemSetPropose(course: Self.graphTheory, material: sheet.id, problems: problems))
        let before = try file()
        #expect(ProblemSetDiscard.spec.asks(ProblemSetDiscard(course: Self.graphTheory, material: sheet.id)))
        try run(ProblemSetDiscard(course: Self.graphTheory, material: sheet.id))
        #expect(try drafts().isEmpty && (try file()) == before)
    }
}
