import FolioDomain
import Foundation
import Testing

@testable import FolioAI

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
            CardRequest(title: "매칭", material: .lecture, count: 2, existing: ["증가 경로"]), context: context)
        #expect(drafts.count == 2 && drafts.allSatisfy { $0.kind == .flip })

        let request = try #require(await fake.requests.first)
        #expect(request.model == TaskConfig.large && request.output_config?.format?.schema == CardDrafts.schema)
        let user = request.messages[0].content.compactMap { if case .text(let t, _) = $0 { t } else { nil } }
        #expect(user.first?.contains("König") == true && user.last?.contains("2장") == true && user.last?.contains("증가 경로") == true)
        #expect(user.last?.contains("렉처 쪽") == true && user.last?.contains("앞뒤 카드(flip)만") == true)

        let unit = UUID(), lecture = UUID()
        let withFile = try #require(drafts[0].card(unitId: unit, materialId: lecture, device: device, at: now))
        let without = try #require(drafts[0].card(unitId: unit, materialId: nil, device: device, at: now))
        #expect(withFile.page == 3 && withFile.materialId == lecture && withFile.source == .claude && withFile.kind == .flip)
        #expect(without.page == nil && without.noteId == nil)
    }

    // 재료가 정리 노트면 노트의 절을 주고, 받은 카드마다 그 노트와 절을 잇는다.
    @Test func cardsFromASummaryNoteAreTiedToItsSections() async throws {
        let reply = #"""
            {"cards":[
            {"kind":"flip","front":"막는 쌍","back":"짝이 아니면서 서로를 지금 짝보다 더 좋아하는 두 사람","answer":null,"section":"용어","page":null},
            {"kind":"true_false","front":"Gale–Shapley의 결과는 제안받는 쪽에게 가장 좋다.","back":"제안하는 쪽에게 가장 좋다.","answer":false,"section":"정리와 증명","page":null},
            {"kind":"true_false","front":"안정 매칭은 언제나 있다.","back":"Gale–Shapley가 만든다.","answer":true,"section":"없는 절","page":null},
            {"kind":"true_false","front":"답이 빠진 문장","back":"이유","answer":null,"section":"용어","page":null},
            {"kind":"flip","front":"뒤가 빈 카드","back":" ","answer":null,"section":null,"page":null}
            ]}
            """#
        let fake = FakeProvider(responses: [FakeProvider.reply(reply)])
        let sections = ["기말 04 안정 매칭", "용어", "정리와 증명"]
        let request = CardRequest(
            title: "기말 04 안정 매칭", material: .note, kinds: [.flip, .trueFalse], count: 5, existing: [], sections: sections)
        let drafts = try await ClaudeClient(provider: fake).suggestCards(
            request, context: [ContextItem(id: "note", title: "정리 노트 기말 04 안정 매칭", tier: .focus, text: "## 용어\n막는 쌍")])

        let sent = try #require(await fake.requests.first)
        let user = sent.messages[0].content.compactMap { if case .text(let t, _) = $0 { t } else { nil } }
        let ask = try #require(user.last)
        #expect(user.first?.contains("막는 쌍") == true)
        #expect(ask.contains("용어, 정리의 내용, 공식, 헷갈리는 것 비교, 자주 하는 실수") && ask.contains("5장"))
        #expect(ask.contains("앞뒤 카드(flip)와 참거짓 카드(true_false)를 섞어") && ask.contains("- 정리와 증명"))
        let system = (sent.system ?? []).compactMap { if case .text(let t, _) = $0 { t } else { nil } }
        #expect(system.contains(MathWriting.rule) && sent.output_config?.format?.schema == CardDrafts.schema)

        let unit = UUID(), note = UUID()
        let cards = drafts.compactMap { $0.card(unitId: unit, noteId: note, sections: sections, device: device, at: now) }
        // 답이 없는 참거짓 카드와 빈 면이 있는 카드는 버린다. 노트에 없는 절은 잇지 않는다.
        #expect(cards.map(\.front) == ["막는 쌍", "Gale–Shapley의 결과는 제안받는 쪽에게 가장 좋다.", "안정 매칭은 언제나 있다."])
        #expect(cards.map(\.kind) == [.flip, .trueFalse, .trueFalse] && cards.map(\.answer) == [nil, false, true])
        #expect(cards.map(\.noteSection) == ["용어", "정리와 증명", nil] && cards.allSatisfy { $0.noteId == note && $0.source == .claude })
        #expect(CardFile(unitId: unit, cards: cards).violations.isEmpty)
        // 노트에 잇지 않는 카드는 절도 가지지 않는다.
        #expect(drafts[0].card(unitId: unit, sections: sections, device: device, at: now)?.noteSection == nil)
    }

    @Test func aCardRequestAsksOnlyForTheChosenKind() {
        let only = ClaudeClient.ask(CardRequest(title: "매칭", material: .textbook, kinds: [.trueFalse], count: 8))
        #expect(only.contains("교재 쪽") && only.contains("참거짓 카드(true_false)만") && only.contains("8장") && !only.contains("노트의 절"))
        #expect(CardRequest(title: "매칭", kinds: [], count: 3).kinds == [.flip])
    }

    @Test func extractedProblemsLinkOnlyKnownUnits() async throws {
        let reply =
            #"{"problems":[{"number":"1","parent":null,"points":10,"page":1,"text":"$K_{3,3}$는 평면 그래프인가?","format":"true_false","options":[],"answer":"거짓","units":["평면 그래프","없는 단원"],"solution":null,"solutionPage":null},{"number":"2","parent":null,"points":null,"page":2,"text":"Hall 정리를 증명하시오.","format":"written","options":["A"],"answer":"","units":["매칭"],"solution":"귀납법","solutionPage":4}]}"#
        let fake = FakeProvider(responses: [FakeProvider.reply(reply)])
        let units = ["매칭", "평면 그래프"].enumerated().map { FolioDomain.Unit(device: device, at: now, title: $0.element, order: $0.offset) }
        let problems = try await ClaudeClient(provider: fake).extractProblems(
            sheet: .pdf(Data("%PDF".utf8)), solution: nil, units: units, source: .pastExam
        ).problems
        #expect(problems.map(\.number) == ["1", "2"])
        #expect(problems[0].unitIds == [units[1].id] && problems[0].options == Problem.trueFalseOptions)
        #expect(problems[1].options.isEmpty && problems[1].answer == nil && problems[1].solution == "귀납법")

        let request = try #require(await fake.requests.first)
        let documents = request.messages[0].content.filter { if case .pdf = $0 { true } else { false } }
        #expect(documents.count == 1)
    }

    // 문제집 PDF의 칸 크기는 Claude가 풀이 분량으로 정한다. 모르는 값과 빠진 값은 정하지 않은 것으로 읽는다. 문제와 풀이는 문제지의
    // 언어와 상관없이 영어로 받는다.
    @Test func extractionReadsTheSizeAndAsksForEnglish() async throws {
        let reply =
            #"{"problems":[{"number":"1","text":"Prove it.","format":"written","options":[],"units":[],"size":"half"},{"number":"2","text":"x","format":"short","options":[],"units":[],"size":"huge"},{"number":"3","text":"y","format":"short","options":[],"units":[]}]}"#
        let fake = FakeProvider(responses: [FakeProvider.reply(reply)])
        let problems = try await ClaudeClient(provider: fake).extractProblems(
            sheet: .pdf(Data("%PDF".utf8)), solution: nil, units: [], source: .pastExam
        ).problems
        #expect(problems.map(\.size) == [.half, nil, nil])
        let request = try #require(await fake.requests.first)
        let system = (request.system ?? []).compactMap { if case .text(let t, _) = $0 { t } else { nil } }.joined()
        #expect(system.contains("full statement in English") && system.contains("Pick \"size\""))
        #expect(ProblemDrafts.schema["properties"]?["problems"]?["items"]?["properties"]?["size"] != nil)
    }

    @Test func extractionNamesEachUnitsLecturePagesAndMapsThePicksBack() async throws {
        let reply =
            #"{"problems":[{"number":"1","parent":null,"points":null,"page":null,"text":"Hall 정리를 쓰시오.","format":"written","options":[],"answer":null,"units":[],"solution":null,"solutionPage":null,"lecturePages":[{"lecture":"L1","page":9},{"lecture":"L9","page":2}]}]}"#
        let fake = FakeProvider(responses: [FakeProvider.reply(reply)])
        let deck = UUID()
        var matching = FolioDomain.Unit(device: device, at: now, title: "매칭", order: 0)
        matching.lecturePages = [UnitPages(materialId: deck, firstPage: 1, lastPage: 12)]
        let lectures = LectureOutline(lectures: [
            LectureOutline.Lecture(materialId: deck, name: "05_Matchings.pdf", pages: [.init(number: 9, title: "Hall's theorem")])
        ])
        let problems = try await ClaudeClient(provider: fake).extractProblems(
            sheet: .tex("\\begin{problem}Hall\\end{problem}"), solution: .pdf(Data("%PDF".utf8)), units: [matching],
            lectures: lectures, source: .exercise
        ).problems
        // 프롬프트에 없는 렉처 이름은 버린다.
        #expect(problems[0].lecturePages == [ProblemPage(materialId: deck, page: 9)])

        let request = try #require(await fake.requests.first)
        let texts = request.messages[0].content.compactMap { if case .text(let t, _) = $0 { t } else { nil } }
        #expect(
            texts[0].contains("- 매칭 (L1 p.1–12)") && texts[0].contains("L1 = 05_Matchings.pdf")
                && texts[0].contains("L1 p.9: Hall's theorem"))
        #expect(texts[1].contains("<latex>") && texts.last == "Solution document:")
        #expect(request.messages[0].content.filter { if case .pdf = $0 { true } else { false } }.count == 1)
    }

    @Test func extractionKeepsTheStemAndTheFigureBoxes() async throws {
        let box = #"{"page":1,"x":0.1,"y":0.2,"width":0.5,"height":0.3}"#
        let outside = #"{"page":1,"x":0.8,"y":0.9,"width":0.5,"height":0.3}"#
        let empty = #"{"page":1,"x":0.1,"y":0.2,"width":0,"height":0.3}"#
        let reply =
            #"{"problems":[{"number":"W1","parent":"W","points":null,"page":1,"text":"Apply the augmenting path algorithm.","format":"written","options":[],"answer":null,"units":[],"solution":null,"solutionPage":null,"lecturePages":[],"region":"#
            + box + #","figures":["# + outside + "," + empty
            + #"]}],"groups":[{"number":"W","title":"Warm-up","parent":null,"page":1,"text":"Warm-up Problems (Do not submit)","region":null,"figures":["#
            + box + "]}]}"
        let fake = FakeProvider(responses: [FakeProvider.reply(reply)])
        let extracted = try await ClaudeClient(provider: fake).extractProblems(
            sheet: .pdf(Data("%PDF".utf8)), solution: nil, units: [], source: .assignment)
        let w1 = try #require(extracted.problems.first)
        #expect(w1.parent == "W" && w1.region == ProblemRegion(page: 1, x: 0.1, y: 0.2, width: 0.5, height: 0.3))
        // 쪽 밖으로 나간 칸은 쪽 안으로 줄이고, 넓이가 없는 칸은 버린다.
        #expect(w1.figures == [ProblemRegion(page: 1, x: 0.8, y: 0.9, width: 0.2, height: 0.1)].compactMap { $0 })
        let group = try #require(extracted.groups.first)
        #expect(group.number == "W" && group.name == "Warm-up" && group.text.hasPrefix("Warm-up") && group.figures.count == 1)

        let request = try #require(await fake.requests.first)
        let system = (request.system ?? []).compactMap { if case .text(let t, _) = $0 { t } else { nil } }.joined()
        // 그림은 문제지에서 잘라 보이므로 글로 풀어 쓰지 않게 한다. 글은 앱이 그리는 LaTeX 부분집합으로 쓰게 한다.
        #expect(system.contains("\"groups\"") && system.contains("Never describe a figure in words") && !system.contains("in brackets"))
        #expect(
            system.contains("LaTeX body source") && system.contains(#"\item[(a)]"#) && system.contains("Never use tables")
                && system.contains("never wrapping a line by hand"))
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
        for schema in [
            ProblemDrafts.schema, CardDrafts.schema, ProblemGrade.schema, SameAnswer.schema, ProblemSheetDraft.schema,
            CollectionGrades.schema, ProblemArtDraft.schema,
        ] {
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
        _ = try await client.extractProblems(sheet: .pdf(Data("%PDF".utf8)), solution: nil, units: [], source: .exercise)
        _ = try await client.suggestCards(CardRequest(title: "연결도", count: 1), context: [])
        _ = try await client.writeProblemSheet(units: [], examples: [], wrong: [], count: 1, context: [])
        let requests = await fake.requests
        #expect(requests.count == 4)
        for request in requests {
            let system = (request.system ?? []).compactMap { if case .text(let t, _) = $0 { t } else { nil } }
            #expect(system.contains(MathWriting.rule))
        }
    }

    // 문제집 그림은 자른 그림을 이미지로 보내고, 지문의 다시 그린 그림 위에 답을 그리게 한다. 검사에 걸린 그림은 그 결과를 붙여
    // 한 번 더 묻는다.
    @Test func problemArtSendsTheCropsAndRetriesWithTheCheck() async throws {
        let reply = #"{"figure":null,"solutionFigure":"<svg viewBox=\"0 0 1 1\"/>","solution":"Match $a_1b_2$."}"#
        let fake = FakeProvider(responses: [FakeProvider.reply(reply), FakeProvider.reply(reply)])
        let stem = ProblemGroup(number: "2", text: "Let $G$ be the graph below.")
        let p = Problem(number: "2b", parent: "2", text: "Find a perfect matching.")
        let job = ProblemArt.Job(id: p.id, set: UUID(), number: "2b", problem: p, stems: [stem], draws: true, writesSolution: true)
        let client = ClaudeClient(provider: fake)
        let draft = try await client.drawProblemArt(job, crops: [Data("png".utf8)], stemFigure: "<svg id=\"stem\"/>")
        #expect(draft.figure == nil && draft.solution == "Match $a_1b_2$.")
        _ = try await client.drawProblemArt(
            job, crops: [], stemFigure: nil, previous: draft, problems: ["label 'a_1' overlaps a line"])

        let requests = await fake.requests
        let first = try #require(requests.first), second = try #require(requests.last)
        #expect(first.model == TaskConfig.large && first.output_config?.format?.schema == ProblemArtDraft.schema)
        let images = first.messages[0].content.filter { if case .image = $0 { true } else { false } }
        let ask = first.messages[0].content.compactMap { if case .text(let t, _) = $0 { t } else { nil } }.joined()
        #expect(images.count == 1 && ask.contains("<stem_figure>") && ask.contains("Write \"solution\""))
        let system = (first.system ?? []).compactMap { if case .text(let t, _) = $0 { t } else { nil } }
        #expect(system.contains(NoteWritingGuide.figureRules) && system.contains(MathWriting.rule))
        #expect(second.messages.map(\.role) == [.user, .assistant, .user])
        let fix = second.messages[2].content.compactMap { if case .text(let t, _) = $0 { t } else { nil } }.joined()
        #expect(fix.contains("overlaps a line"))
    }

    // 문제마다 칸 머리의 이름표를 보내고, 답의 차례를 문제 ID로 바꾼다. 없는 차례와 두 번 온 차례는 버린다.
    @Test func aCollectionIsGradedFromOnePDF() async throws {
        let reply = #"""
            {"grades":[{"item":2,"verdict":"wrong","reason":"time","feedback":["7번을 쓰지 못했어요."],"page":null},
            {"item":1,"verdict":"correct","reason":"concept","feedback":[],"page":3},
            {"item":1,"verdict":"wrong","reason":null,"feedback":[],"page":4},
            {"item":9,"verdict":"correct","reason":null,"feedback":[],"page":1}]}
            """#
        let fake = FakeProvider(responses: [FakeProvider.reply(reply)])
        let first = Problem(number: "1", text: "Prove Hall's theorem.", solution: "By induction on $|X|$.")
        let second = Problem(number: "2b", parent: "2", text: "Find a perfect matching.")
        let stem = ProblemGroup(number: "2", text: "Let $G$ be the graph below.")
        let grades = try await ClaudeClient(provider: fake).gradeCollection(
            [CollectionProblem(set: "2024 Midterm", problem: first), CollectionProblem(set: "HW03", problem: second, stems: [stem])],
            submitted: Data("%PDF".utf8), mock: true)

        #expect(grades.map(\.problem) == [second.id, first.id])
        #expect(grades[0].outcome.grade.reason == .time && grades[0].outcome.basis == .claude && grades[0].page == nil)
        // 맞은 문제의 이유는 버린다.
        #expect(grades[1].outcome.grade.reason == nil && grades[1].outcome.basis == .solution && grades[1].page == 3)

        let request = try #require(await fake.requests.first)
        #expect(request.messages[0].content.contains { if case .pdf = $0 { true } else { false } })
        let ask = request.messages[0].content.compactMap { if case .text(let t, _) = $0 { t } else { nil } }.joined()
        #expect(ask.contains(#"label="HW03 – Problem 2b""#) && ask.contains("<stem>\nLet $G$"))
        let system = (request.system ?? []).compactMap { if case .text(let t, _) = $0 { t } else { nil } }.joined()
        #expect(system.contains("time: stopped") && system.contains(MathWriting.rule))
    }
}
