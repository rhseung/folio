import FolioAI
import FolioDomain
import Foundation
import Testing

struct StudyAITests {
    let device = UUID(), now = Date()

    @Test func cardsComeFromTheContextAndKeepPagesOnlyWithAFile() async throws {
        let reply =
            #"{"cards":[{"front":"매칭","back":"공통 끝점이 없는 변의 집합","page":3},{"front":"König 정리","back":"이분 그래프에서 최대 매칭의 크기는 최소 정점 덮개의 크기와 같다","page":null}]}"#
        let fake = FakeProvider(responses: [FakeProvider.reply(reply)])
        let context = [
            ContextItem(id: "note", title: "노트 8주차-1", tier: .focus, text: "> [!theorem] König"),
            ContextItem(id: "course", title: "과목 요약", tier: .courseSummary, text: "과목: 그래프 이론"),
        ]
        let drafts = try await ClaudeClient(provider: fake).suggestCards(
            unitTitle: "매칭", count: 2, existing: ["증가 경로"], context: context)
        #expect(drafts.count == 2)

        let request = try #require(await fake.requests.first)
        #expect(request.model == TaskConfig.large && request.output_config?.format?.schema == CardDrafts.schema)
        let user = request.messages[0].content.compactMap { if case .text(let t, _) = $0 { t } else { nil } }
        #expect(user.first?.contains("König") == true && user.last?.contains("2장") == true && user.last?.contains("증가 경로") == true)

        let unit = UUID(), lecture = UUID()
        let withFile = drafts[0].card(unitId: unit, materialId: lecture, device: device, at: now)
        let without = drafts[0].card(unitId: unit, materialId: nil, device: device, at: now)
        #expect(withFile.page == 3 && withFile.materialId == lecture && withFile.source == .claude)
        #expect(without.page == nil)
    }

    @Test func extractedProblemsLinkOnlyKnownUnits() async throws {
        let reply =
            #"{"problems":[{"number":"1","parent":null,"points":10,"page":1,"text":"$K_{3,3}$는 평면 그래프인가?","format":"true_false","options":[],"answer":"거짓","units":["평면 그래프","없는 단원"],"solution":null,"solutionPage":null},{"number":"2","parent":null,"points":null,"page":2,"text":"Hall 정리를 증명하시오.","format":"written","options":["A"],"answer":"","units":["매칭"],"solution":"귀납법","solutionPage":4}]}"#
        let fake = FakeProvider(responses: [FakeProvider.reply(reply)])
        let units = ["매칭", "평면 그래프"].enumerated().map { FolioDomain.Unit(device: device, at: now, title: $0.element, order: $0.offset) }
        let problems = try await ClaudeClient(provider: fake).extractProblems(
            sheet: Data("%PDF".utf8), solution: nil, units: units, source: .pastExam)
        #expect(problems.map(\.number) == ["1", "2"])
        #expect(problems[0].unitIds == [units[1].id] && problems[0].options == Problem.trueFalseOptions)
        #expect(problems[1].options.isEmpty && problems[1].answer == nil && problems[1].solution == "귀납법")

        let request = try #require(await fake.requests.first)
        let documents = request.messages[0].content.filter { if case .pdf = $0 { true } else { false } }
        #expect(documents.count == 1)
    }

    @Test func gradingSendsTheSolutionOrAsksClaudeToSolve() async throws {
        let fake = FakeProvider(responses: [
            FakeProvider.reply(#"{"verdict":"wrong","reason":"concept","feedback":["방향을 하나 빠뜨렸습니다."],"lines":[]}"#),
            FakeProvider.reply(#"{"verdict":"correct","reason":null,"feedback":[],"lines":[]}"#),
        ])
        let client = ClaudeClient(provider: fake)
        let solved = Problem(number: "3", text: "Q", solution: "쉬운 방향과 어려운 방향")
        let first = try await client.gradeProblem(solved, answer: "x")
        #expect(first.verdict == .wrong && first.reason == .concept && first.feedback.count == 1)
        _ = try await client.gradeProblem(Problem(number: "4", text: "Q"), answer: "y")

        func text(_ i: Int) async -> String {
            guard case .text(let t, _)? = await fake.requests[i].messages.first?.content.last else { return "" }
            return t
        }
        #expect(await text(0).contains("<solution>\n쉬운 방향과 어려운 방향\n</solution>"))
        #expect(await text(1).contains("solve it yourself first"))
    }

    @Test func aShortAnswerKeyMatchesWithoutClaude() {
        let p = Problem(number: "1", text: "Q", format: .short, answer: "$\\frac{1}{2}$")
        #expect(p.keyVerdict(for: " \\frac{1}{2} ") == .correct)
        #expect(p.keyVerdict(for: "0.5") == nil)
        let tf = Problem(number: "2", text: "Q", format: .trueFalse, options: Problem.trueFalseOptions, answer: "거짓")
        #expect(tf.keyVerdict(for: "참") == .wrong && tf.keyVerdict(for: "거짓") == .correct)
    }

    @Test func gradingUsesTheKeyThenTheSolutionThenClaudesOwnAnswer() async throws {
        let fake = FakeProvider(responses: [
            FakeProvider.reply(#"{"same":true}"#),
            FakeProvider.reply(#"{"verdict":"partial","reason":"method","feedback":[],"lines":[]}"#),
            FakeProvider.reply(#"{"verdict":"correct","reason":null,"feedback":[],"lines":[]}"#),
        ])
        let client = ClaudeClient(provider: fake)
        let tf = Problem(number: "1", text: "Q", format: .trueFalse, options: Problem.trueFalseOptions, answer: "참")
        #expect(try await client.grade(tf, answer: "거짓") == GradeOutcome(grade: ProblemGrade(verdict: .wrong), basis: .key))
        #expect(await fake.requests.isEmpty)

        let short = Problem(number: "2", text: "Q", format: .short, answer: "3")
        #expect(try await client.grade(short, answer: "three").basis == .key)
        let solved = Problem(number: "3", text: "Q", solution: "S")
        #expect(
            try await client.grade(solved, answer: "x")
                == GradeOutcome(grade: ProblemGrade(verdict: .partial, reason: .method), basis: .solution))
        #expect(try await client.grade(Problem(number: "4", text: "Q"), answer: "y").basis == .claude)
        #expect(await fake.requests.count == 3)
    }

    @Test func schemasAreStrict() {
        for schema in [ProblemDrafts.schema, CardDrafts.schema, ProblemGrade.schema, SameAnswer.schema, ProblemSheetDraft.schema] {
            #expect(schema["additionalProperties"] == .bool(false))
        }
    }

    // 공부 글을 쓰는 작업은 모두 수식을 `$…$`로 쓰라는 규칙을 받는다. 유니코드 기호로 쓴 수식은 앱이 그리지 못한다.
    @Test func everyStudyTaskAsksForLaTeXMath() async throws {
        let fake = FakeProvider(responses: [
            FakeProvider.reply(#"{"verdict":"correct","reason":null,"feedback":["$\\kappa(G) = 4$이므로 맞습니다."],"lines":[]}"#),
            FakeProvider.reply(#"{"problems":[]}"#),
            FakeProvider.reply(#"{"cards":[]}"#),
            FakeProvider.reply(#"{"title":"모의","problems":[]}"#),
        ])
        let client = ClaudeClient(provider: fake)
        _ = try await client.gradeProblem(Problem(number: "1", text: "$\\kappa(G) = 4$이면 $G$는 2-연결인가?"), answer: "참")
        _ = try await client.extractProblems(sheet: Data("%PDF".utf8), solution: nil, units: [], source: .exercise)
        _ = try await client.suggestCards(unitTitle: "연결도", count: 1, existing: [], context: [])
        _ = try await client.writeProblemSheet(units: [], examples: [], wrong: [], count: 1, context: [])
        let requests = await fake.requests
        #expect(requests.count == 4)
        for request in requests {
            let system = (request.system ?? []).compactMap { if case .text(let t, _) = $0 { t } else { nil } }
            #expect(system.contains(MathWriting.rule))
        }
    }
}
