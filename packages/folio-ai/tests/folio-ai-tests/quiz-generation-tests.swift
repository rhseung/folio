import FolioAI
import FolioDomain
import Foundation
import Testing

struct QuizGenerationTests {
    @Test func makesCardsFromNotesThroughContextBuilder() async throws {
        let reply = #"{"cards":[{"type":"proof","category":"theorem","prompt":"König 정리를 증명하시오.","options":[],"answer":"...","rubric":["Hall 조건"]},{"type":"choice","category":"definition","prompt":"매칭이란?","options":["A","B","C","D"],"answer":"B","rubric":[]},{"type":"choice","category":"concept","prompt":"잘못된 카드","options":["A","B"],"answer":"Z","rubric":[]},{"type":"true_false","category":"concept","prompt":"트리는 연결 그래프다.","options":[],"answer":"참","rubric":[]}]}"#
        let fake = FakeProvider(responses: [FakeProvider.reply(reply)])
        let context = [
            ContextItem(id: "note", title: "노트 8주차-1", tier: .focus, text: "> [!theorem] König"),
            ContextItem(id: "course", title: "과목 요약", tier: .courseSummary, text: "과목: 그래프 이론"),
        ]
        let drafts = try await ClaudeClient(provider: fake).makeCards(unitTitle: "Matchings", count: 4, type: nil, context: context)
        #expect(drafts.count == 4)

        let request = try #require(await fake.requests.first)
        #expect(request.model == TaskConfig.large && request.output_config?.format?.schema == QuizCardDrafts.schema)
        guard case .text(let summary, true)? = request.system?.first else { Issue.record("cached summary first"); return }
        #expect(summary.contains("그래프 이론"))
        let user = request.messages[0].content.compactMap { if case .text(let t, _) = $0 { t } else { nil } }
        #expect(user.first?.contains("König") == true && user.last?.contains("4장") == true)

        let unit = UUID(), device = UUID(), now = Date()
        let cards = drafts.compactMap { $0.card(unitId: unit, device: device, at: now) }
        // The choice card whose answer isn't among its options is dropped.
        #expect(cards.map(\.type) == [.proof, .choice, .trueFalse])
        #expect(cards.allSatisfy { $0.source == .ai && $0.unitId == unit })
        #expect(cards[2].options == QuizCard.trueFalseOptions && cards[0].options.isEmpty)
        #expect(cards[1].verdict(choosing: "B") == .correct && cards[1].verdict(choosing: "A") == .wrong)
    }

    @Test func gradingResultBecomesTheAttemptEvent() async throws {
        let fake = FakeProvider(responses: [FakeProvider.reply(#"{"verdict":"wrong","missing":["쉬운 방향"],"feedback":"방향을 하나 빠뜨렸습니다.","lines":[]}"#)])
        let result = try await ClaudeClient(provider: fake).grade(question: "Q", modelAnswer: "A", rubric: ["쉬운 방향"], answer: "x", rules: "")
        let event = QuizAttemptEvent(cardId: UUID(), answer: "x", verdict: Verdict(rawValue: result.verdict.rawValue)!, grader: .ai, missing: result.missing)
        #expect(event.verdict == .wrong && event.missing == ["쉬운 방향"])
        guard case .text(let text, _)? = await fake.requests.first?.messages.first?.content.last else { Issue.record("text"); return }
        #expect(text.contains("<rubric>\n- 쉬운 방향\n</rubric>"))
    }

    @Test func draftSchemaIsStrict() {
        guard case .object(let props)? = QuizCardDrafts.schema["properties"],
              case .object(let item)? = props["cards"]?["items"] else { Issue.record("shape"); return }
        #expect(QuizCardDrafts.schema["additionalProperties"] == .bool(false))
        #expect(item["additionalProperties"] == .bool(false))
    }
}
