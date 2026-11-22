import FolioAI
import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

@testable import Folio

@MainActor
struct ProblemExtractionModelTests {
    let workspace: Workspace

    static let reply =
        #"{"problems":[{"number":"1","parent":null,"points":10,"page":1,"text":"$K_{3,3}$는 평면 그래프인가?","format":"true_false","options":[],"answer":"거짓","units":[],"solution":null,"solutionPage":null},{"number":"2","parent":null,"points":null,"page":2,"text":"Hall 정리를 증명하시오.","format":"written","options":[],"answer":null,"units":["매칭"],"solution":null,"solutionPage":null}]}"#

    init() throws {
        workspace = try fixtureWorkspace()
    }

    func answer(_ count: Int) -> FakeProvider {
        FakeProvider(responses: Array(repeating: FakeProvider.reply(Self.reply), count: count))
    }

    func track() {
        workspace.run(MaterialTrack(course: graphTheory, assignments: false))
    }

    func material(_ path: String) throws -> Material {
        try #require(workspace.course(graphTheory)?.file.materials.first { $0.path == path })
    }

    func drafts() throws -> [StudyDraft] {
        try #require(workspace.course(graphTheory)).store.drafts().map(\.model)
    }

    @Test func theMenuProposesAndTheNoticeAcceptsEverything() async throws {
        track()
        let matching = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        let fake = answer(1)
        workspace.extractor.standIn = { _ in ClaudeClient(provider: fake) }
        let sheet = try material("Inherited/소순범/2024 Midterm.pdf")
        let model = ProblemsModel(workspace: workspace, courseId: graphTheory)

        workspace.extractProblems(from: sheet.id, in: graphTheory)
        #expect(model.extractions.map(\.phase) == [.working])
        await workspace.extractor.finish()

        let notice = try #require(model.extractions.first)
        #expect(model.extractions.count == 1 && notice.phase == .ready && notice.material == sheet.id)
        #expect(notice.title.contains("2024 Midterm.pdf") && notice.title.contains("2"))
        // 해설은 이름으로 짝지어 함께 보낸다.
        #expect(notice.detail?.contains("2024 Midterm Solution.pdf") == true)
        #expect(await fake.requests.count == 1)
        #expect(workspace.course(graphTheory)?.file.problemSets.contains { $0.materialId == sheet.id } == false)

        model.acceptAll(notice)
        let set = try #require(workspace.course(graphTheory)?.file.problemSets.first { $0.materialId == sheet.id })
        #expect(set.problems.map(\.number) == ["1", "2"] && set.source == .pastExam)
        #expect(set.problems[1].unitIds == [matching])
        let left = try drafts()
        #expect(model.extractions.isEmpty && left.isEmpty)
    }

    @Test func newSheetsAreExtractedOnTheirOwnWhenRegistered() async throws {
        let fake = answer(20)
        workspace.extractor.standIn = { _ in ClaudeClient(provider: fake) }
        track()
        await workspace.extractor.finish()

        let file = try #require(workspace.course(graphTheory)?.file)
        let expected = Set(file.materials.filter { ProblemExtraction.automatic($0, in: file) }.map(\.id))
        let drafted = Set(try drafts().compactMap(\.materialId))
        let exam = try material("Inherited/소순범/2024 Midterm.pdf"), solution = try material("Inherited/소순범/2024 Midterm Solution.pdf")
        #expect(!expected.isEmpty && drafted == expected)
        #expect(drafted.contains(exam.id) && !drafted.contains(solution.id))
        #expect(await fake.requests.count == expected.count)

        // 끄면 새 자료를 뽑지 않는다.
        var settings = workspace.settings
        settings.study.autoExtract = false
        workspace.saveSettings(settings)
        try Data("문제".utf8).write(to: try #require(workspace.course(graphTheory)).store.url.appending(path: "Exercises/Exercise 9.pdf"))
        track()
        await workspace.extractor.finish()
        #expect(await fake.requests.count == expected.count)
    }

    @Test func aFailureCanBeRetriedOrDismissed() async throws {
        track()
        workspace.extractor.standIn = { _ in ClaudeClient(provider: FakeProvider(responses: [])) }
        let sheet = try material("Exercises/Exercise 1.pdf")
        let model = ProblemsModel(workspace: workspace, courseId: graphTheory)
        workspace.extractProblems(from: sheet.id, in: graphTheory)
        await workspace.extractor.finish()
        #expect(model.extractions.map(\.phase) == [.failed])

        let fake = answer(1)
        workspace.extractor.standIn = { _ in ClaudeClient(provider: fake) }
        model.retry(try #require(model.extractions.first))
        await workspace.extractor.finish()
        #expect(model.extractions.map(\.phase) == [.ready])

        workspace.extractor.standIn = { _ in ClaudeClient(provider: FakeProvider(responses: [])) }
        let other = try material("Inherited/소순범/2024 Midterm.pdf")
        workspace.extractProblems(from: other.id, in: graphTheory)
        await workspace.extractor.finish()
        let failed = try #require(model.extractions.first { $0.phase == .failed })
        model.dismiss(failed)
        #expect(model.extractions.map(\.material) == [sheet.id])
    }

    @Test func theReviewKeepsOnlyTheCheckedProblemsUnderTheGivenTitle() throws {
        track()
        let sheet = try material("Exercises/Exercise 1.pdf")
        let problems = [Problem(number: "1", page: 1, text: "첫 문제"), Problem(number: "2", page: 2, text: "둘째 문제")]
        workspace.run(ProblemSetPropose(course: graphTheory, material: sheet.id, problems: problems))
        let course = try #require(workspace.course(graphTheory))

        let model = ProblemDraftModel(workspace: workspace, course: course, material: sheet.id)
        #expect(model.title == "Exercise 1" && model.rows.map(\.problem.number) == ["1", "2"])
        model.toggle(model.rows[0].id)
        model.title = "연습 1"
        #expect(model.canAccept)
        #expect(model.accept())
        let set = try #require(workspace.course(graphTheory)?.file.problemSets.first { $0.materialId == sheet.id })
        #expect(set.title == "연습 1" && set.problems.map(\.number) == ["2"])

        model.title = " "
        #expect(!model.canAccept)
    }

    @Test func discardingTheReviewAsksFirst() throws {
        track()
        let sheet = try material("Exercises/Exercise 1.pdf")
        workspace.run(ProblemSetPropose(course: graphTheory, material: sheet.id, problems: [Problem(number: "1", text: "문제")]))
        let model = ProblemDraftModel(workspace: workspace, course: try #require(workspace.course(graphTheory)), material: sheet.id)
        model.discard()
        let waiting = try drafts()
        #expect(!waiting.isEmpty && !model.finished)
        try #require(model.pending).perform()
        let left = try drafts()
        #expect(left.isEmpty && model.finished)
    }
}
