import FolioAI
import FolioActions
import FolioDomain
import FolioStorage
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

    // Claude가 있으면 문제집을 만들기 전에 문제지 PDF가 있는 문제의 그림을 다시 그리고, 풀이가 없는 문제의 풀이를 쓴다.
    // 다시 그린 그림은 문제집에 자른 그림 대신 들어간다.
    @Test func handwritingRedrawsFiguresAndWritesMissingSolutions() async throws {
        let workspace = try fixtureWorkspace()
        workspace.run(MaterialTrack(course: graphTheory, assignments: false))
        let unit = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        let sheet = try #require(workspace.course(graphTheory)?.file.materials.first { $0.path == "Inherited/소순범/2024 Midterm.pdf" })
        let figure = try #require(ProblemRegion(page: 1, x: 0.1, y: 0.2, width: 0.4, height: 0.3))
        let problems = [
            Problem(number: "1", text: "Find a perfect matching of $G$.", format: .written, unitIds: [unit], figures: [figure]),
            Problem(number: "2", text: "State Hall's theorem.", format: .written, unitIds: [unit]),
        ]
        workspace.run(ProblemSetAdd(course: graphTheory, title: "2024 Midterm", material: sheet.id, problems: problems))

        let svg =
            #"<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 40 20\"><line class=\"s-ink\" x1=\"2\" y1=\"10\" x2=\"38\" y2=\"10\"/></svg>"#
        let reply = #"{"figure":"\#(svg)","solutionFigure":"\#(svg)","solution":"By Hall's theorem."}"#
        let fake = FakeProvider(responses: Array(repeating: FakeProvider.reply(reply), count: 2))
        let model = SolveModel(workspace: workspace, request: SolveRequest(course: graphTheory, units: [unit], mode: .handwriting))
        model.claudeStandIn = ClaudeClient(provider: fake)
        await model.buildCollection()
        #expect(model.collectionFailure == nil && model.undrawn == 0 && model.collection != nil)
        #expect(await fake.requests.count == 2)

        let course = try #require(workspace.course(graphTheory))
        let saved = try #require(course.file.problemSets.first { $0.title == "2024 Midterm" })
        #expect(saved.problems.allSatisfy { $0.solution == "By Hall's theorem." })
        let art = course.store.problemArt()
        #expect(art.keys.sorted() == [saved.problems[0].id] && art.values.first?.model.solutionFigure != nil)
        let files = ProblemCollectionFiles(store: course.store, file: course.file, semester: nil, author: "", problems: [])
        let tex = try String(contentsOf: files.problemsTeX, encoding: .utf8)
        #expect(tex.contains("\\artfigure{art-\(saved.problems[0].id.uuidString).pdf}"))
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
