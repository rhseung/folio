import FolioActions
import FolioDomain
import Foundation
import Testing

@testable import Folio

@MainActor
struct SolveModelTests {
    func solvable() throws -> (Workspace, UUID) {
        let workspace = try fixtureWorkspace()
        let unit = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        let problems = ["참", "거짓"].enumerated().map { i, key in
            Problem(number: "\(i + 1)", text: "문제 \(i + 1)", format: .trueFalse, answer: key, unitIds: [unit])
        }
        workspace.run(ProblemSetAdd(course: graphTheory, title: "연습 1", problems: problems))
        return (workspace, unit)
    }

    @Test func aKeyedProblemGradesAtOnceAndOnlyGradedOnesAreLogged() throws {
        let (workspace, unit) = try solvable()
        let model = SolveModel(workspace: workspace, request: SolveRequest(course: graphTheory, units: [unit]))
        #expect(model.phase == .setup && model.picked.count == 2)

        model.start()
        model.choose("참")
        #expect(model.graded?.verdict == .correct && model.graded?.basis == .key)
        model.next()
        model.choose("참")
        #expect(model.graded?.verdict == .wrong)
        model.next()
        #expect(model.phase == .done && model.wrongCount == 1)
        #expect(workspace.study(of: graphTheory)?.allProblems.filter { $0.status.needsWork }.count == 1)

        model.retryWrong()
        #expect(model.phase == .solving && model.current?.problem.number == "2")
    }

    // 필기로 풀 때 고른 문제로 문제집과 풀이집 PDF를 Study에 만들고, 고른 문제가 바뀌면 다시 만들게 한다.
    @Test func handwritingBuildsTheCollectionOfThePickedProblems() async throws {
        let (workspace, unit) = try solvable()
        let model = SolveModel(workspace: workspace, request: SolveRequest(course: graphTheory, units: [unit], mode: .handwriting))
        await model.buildCollection()
        #expect(model.collectionFailure == nil)
        let collection = try #require(model.collection)
        #expect(collection.url.lastPathComponent == "EC4207-Practice-Problems.pdf")
        #expect(model.collectionIsCurrent && collection.problemsMaterial != nil && collection.solutionsMaterial != nil)
        let materials = try #require(workspace.course(graphTheory)?.file.materials)
        #expect(materials.contains { $0.id == collection.problemsMaterial && $0.builtHash == $0.hash })

        #expect(collection.problems.count == 2)
        model.count = 1
        #expect(!model.collectionIsCurrent)
    }

    @Test func aSkippedProblemLeavesNoRecord() throws {
        let (workspace, unit) = try solvable()
        let model = SolveModel(workspace: workspace, request: SolveRequest(course: graphTheory, units: [unit]))
        model.start()
        model.next()
        model.next()
        #expect(model.phase == .done && model.unitResults().isEmpty)
        #expect(workspace.study(of: graphTheory)?.allProblems.allSatisfy { $0.attempts.isEmpty } == true)
    }

    @Test func aMockKeepsAnswersUntilItIsHandedIn() throws {
        let (workspace, unit) = try solvable()
        let model = SolveModel(workspace: workspace, request: SolveRequest(course: graphTheory, units: [unit], mode: .mock))
        model.start()
        model.choose("참")
        #expect(model.graded == nil)
        model.next()
        model.back()
        #expect(model.answer == "참")
    }

    // 문제지 1쪽 단추는 PDF의 첫 쪽(0번)을 연다.
    // 문제의 쪽과 링크의 쪽은 모두 1부터 센다. 한쪽만 0부터 세면 문제지 1쪽 단추가 2쪽을 연다.
    @Test func aPageLinkOpensTheProblemsOwnPage() {
        let material = UUID()
        #expect(SolveModel.PageLink(material: material, page: 1).link == AppLink(.material, material, anchor: .page(1)))
        #expect(SolveModel.PageLink(material: material, page: 3).link.anchor == .page(3))
        #expect(SolveModel.PageLink(material: material, page: nil).link == AppLink(.material, material))
    }

    // 풀기는 주소로 열리므로, 주소로 다시 만든 요청이 처음 요청과 같아야 기록이 같은 풀기로 돌아온다.
    @Test func aSolveRequestSurvivesItsLink() throws {
        let request = SolveRequest(
            course: UUID(), units: [UUID()], set: UUID(), problems: [UUID(), UUID()], planItem: UUID(), mode: .mock, shuffled: true,
            minutes: 40)
        let link = try #require(AppLink(string: request.link.string))
        let query = try #require(link.solve)
        #expect(SolveRequest(course: request.course, query: query) == request)
    }
}
