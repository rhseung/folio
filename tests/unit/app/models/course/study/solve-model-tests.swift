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

    func paper(_ workspace: Workspace, _ unit: UUID, _ mode: SolveMode = .handwriting) throws -> SolveSheetModel {
        let model = SolveModel(workspace: workspace, request: SolveRequest(course: graphTheory, units: [unit], mode: mode))
        model.start()
        return try #require(model.sheet)
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

    // 필기로 풀면 고른 문제로 문제집과 풀이집 PDF를 Study에 만든다.
    @Test func handwritingBuildsTheCollectionOfThePickedProblems() async throws {
        let (workspace, unit) = try solvable()
        let model = try paper(workspace, unit)
        await model.buildCollection()
        #expect(model.collectionFailure == nil && model.rows.count == 2)
        let collection = try #require(model.collection)
        #expect(collection.url.lastPathComponent == "EC4207-Practice-Problems.pdf")
        #expect(collection.problemsMaterial != nil && collection.solutionsMaterial != nil)
        let materials = try #require(workspace.course(graphTheory)?.file.materials)
        #expect(materials.contains { $0.id == collection.problemsMaterial && $0.builtHash == $0.hash })
    }

    // 화면에서는 서술형을 풀지 않는다. 고르기는 서술형을 빼고, 서술형이 든 문제를 정해 열면 문제집 페이지로 연다(#577).
    @Test func writtenProblemsGoToPaper() throws {
        let (workspace, unit) = try solvable()
        let written = Problem(number: "3", text: "Prove Hall's theorem.", format: .written, unitIds: [unit])
        workspace.run(ProblemSetAdd(course: graphTheory, title: "연습 2", problems: [written]))
        let typing = SolveModel(workspace: workspace, request: SolveRequest(course: graphTheory, units: [unit]))
        #expect(typing.picked.count == 2)
        typing.mode = .handwriting
        #expect(typing.picked.count == 3)

        let saved = try #require(workspace.study(of: graphTheory)?.allProblems.first { $0.problem.number == "3" })
        let opened = SolveModel(workspace: workspace, request: SolveRequest(course: graphTheory, problems: [saved.problem.id]))
        #expect(opened.mode == .handwriting && opened.sheet?.rows.map(\.id) == [saved.problem.id])
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
        let model = try paper(workspace, unit)
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

    // 고쳐도 검사에 걸리는 그림은 파일로 남기지 않는다. 파일이 있으면 다음 문제집이 그 문제를 다시 그리지 않는다.
    @Test func aRejectedFigureIsDrawnAgainNextTime() async throws {
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

        let reply = #"{"figure":"<div/>","solutionFigure":null,"solution":"By Hall's theorem."}"#
        let fake = FakeProvider(responses: Array(repeating: FakeProvider.reply(reply), count: 3))
        let model = try paper(workspace, unit)
        model.claudeStandIn = ClaudeClient(provider: fake)
        await model.buildCollection()
        // 픽스처의 문제지 PDF는 열리지 않는 자리표시자라 자른 그림으로 돌아간 문제집은 TeX이 만들지 못한다. 그래서 문제집은 보지 않는다.
        #expect(model.undrawn == 1)
        // 그리는 문제는 처음과 고쳐 달라는 재요청, 풀이만 쓰는 문제는 한 번이다.
        #expect(await fake.requests.count == 3)

        let course = try #require(workspace.course(graphTheory))
        #expect(course.store.problemArt().isEmpty)
        let saved = try #require(course.file.problemSets.first { $0.title == "2024 Midterm" })
        #expect(saved.problems.allSatisfy { $0.solution == "By Hall's theorem." })
        #expect(ProblemArtDrawing.jobs(course, picked: saved.problems.map(\.id)).map(\.number) == ["1"])
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

    // 푼 PDF 한 벌을 한 번에 채점해 문제마다 기록하고, 낸 PDF는 Study에 남긴다. 답에 없는 문제는 남은 문제로만 다시 채점하고,
    // 판정을 바꾸면 바꾼 판정이 최종이다. 모의시험은 문제집이 생긴 때부터 시간을 잰다.
    @Test func aHandedInCollectionIsGradedAtOnce() async throws {
        let (workspace, unit) = try solvable()
        let model = try paper(workspace, unit, .mock)
        await model.buildCollection()
        #expect(model.started != nil && model.deadline != nil)
        let second = try #require(model.rows.last?.id)

        let fake = FakeProvider(responses: [
            FakeProvider.reply(#"{"grades":[{"item":1,"verdict":"correct","reason":null,"feedback":[],"page":2}]}"#),
            FakeProvider.reply(#"{"grades":[{"item":1,"verdict":"wrong","reason":"time","feedback":["쓰지 못했어요."],"page":null}]}"#),
        ])
        model.claudeStandIn = ClaudeClient(provider: fake)
        let pdf = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".pdf")
        try Data("%PDF-1.4".utf8).write(to: pdf)
        model.submit(pdf)
        #expect(model.canGrade)
        await model.grade()
        #expect(model.rows.first?.graded?.verdict == .correct && model.rows.first?.page == 2 && model.ungraded.map(\.id) == [second])
        #expect(model.gradeFailure != nil)

        await model.grade()
        #expect(model.ungraded.isEmpty && model.rows.last?.graded?.reason == .time)
        let asked = await fake.requests.last?.messages[0].content.compactMap { if case .text(let t, _) = $0 { t } else { nil } }.joined()
        #expect(asked?.contains("문제 2") == true && asked?.contains("문제 1") == false)
        let materials = try #require(workspace.course(graphTheory)?.file.materials)
        #expect(materials.filter { $0.path.hasPrefix("Study/EC4207-Practice-Answers") }.count == 1)

        model.override(second, .correct)
        let records = try #require(workspace.study(of: graphTheory)?.allProblems)
        #expect(records.allSatisfy { $0.attempts.count == 1 && $0.status.needsWork == false })
        #expect(model.rows.last?.graded?.reason == nil && model.resultLine.contains("2"))
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
