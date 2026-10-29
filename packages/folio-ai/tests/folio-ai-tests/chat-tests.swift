@testable import FolioAI
import FolioDomain
import Foundation
import Testing

struct ChatTests {
    let device = UUID(), now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func panelContextKeepsSummaryAndRulesAndHonorsRemovals() {
        let file = CourseFile(course: Course(device: device, at: now, title: "선형대수학"))
        let noteID = UUID()
        let open = ContextBuilder.note(id: noteID, title: "3주차", body: "고유값", open: true)
        let added = [
            ContextBuilder.note(id: noteID, title: "3주차", body: "고유값", open: false),
            ContextBuilder.material(path: "Lectures/03_eigen.pdf", text: "Eigenvalues"),
        ]
        let items = ContextBuilder.chatItems(course: file, rules: "정의는 전제부터", openNote: open, added: added, removed: [], now: now)
        #expect(items.map(\.id) == ["course:\(file.course.id)", "rules", "note:\(noteID)", "material:Lectures/03_eigen.pdf"])
        #expect(items[2].tier == .focus)

        let fewer = ContextBuilder.chatItems(course: file, rules: "r", openNote: open, added: added, removed: ["material:Lectures/03_eigen.pdf"], now: now)
        #expect(fewer.map(\.id).contains("material:Lectures/03_eigen.pdf") == false)
        #expect(ContextBuilder.chatItems(course: file, rules: "r", openNote: nil, added: [], removed: [], now: now).count == 2)
    }

    @Test func replySendsHistoryAndPutsContextBeforeTheNewQuestion() async throws {
        let fake = FakeProvider(responses: [FakeProvider.reply("$\\lambda$ 는 고유값입니다")])
        let file = CourseFile(course: Course(device: device, at: now, title: "선형대수학"))
        let items = ContextBuilder.chatItems(course: file, rules: "규칙", openNote: ContextBuilder.note(id: UUID(), title: "3주차", body: "본문", open: true),
                                             added: [], removed: [], now: now)
        var chat = Chat(device: device, at: now)
        chat.messages = [
            ChatMessage(role: .user, text: "첫 질문", at: now),
            ChatMessage(role: .assistant, text: "첫 답", at: now),
            ChatMessage(role: .user, text: "고유값이 뭐야?", at: now),
        ]
        let response = try await ClaudeClient(provider: fake).reply(to: chat, context: ContextBuilder.build(items, budgetTokens: 1_000))
        #expect(response.text.contains("고유값"))

        let r = try #require(await fake.requests.first)
        #expect(r.model == TaskConfig.defaults(for: .chat).model)
        #expect(r.messages.map(\.role) == [.user, .assistant, .user])
        #expect(r.messages[0].content == [.text("첫 질문")])
        #expect(r.messages[2].content == [.text("<열린 노트: 3주차>\n본문\n</열린 노트: 3주차>"), .text("고유값이 뭐야?")])
        guard case .text(let stable, let cache)? = r.system?.last else { Issue.record("no system"); return }
        #expect(cache && stable.contains("과목: 선형대수학") && stable.contains("규칙"))
    }

    @Test func replyNeedsAQuestion() async {
        let chat = Chat(device: device, at: now, messages: [ChatMessage(role: .assistant, text: "a", at: now)])
        await #expect(throws: ClaudeError.self) {
            try await ClaudeClient(provider: FakeProvider(responses: [])).reply(to: chat, context: ContextBuilder.build([], budgetTokens: 10))
        }
    }

    @Test func monthlyUsageSumsTokensAndCost() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let oct = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23))!
        let nov = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 1))!
        let opus = APIUsageEvent(task: .chat, model: "claude-opus-5-5",
                                 usage: Usage(input_tokens: 1_000, output_tokens: 500, cache_creation_input_tokens: 2_000, cache_read_input_tokens: 10_000))
        let unknown = APIUsageEvent(task: .chat, model: "claude-unknown", usage: Usage(input_tokens: 7, output_tokens: 3))
        let months = APIUsageEvent.monthly([(oct, opus), (oct, opus), (nov, unknown)], calendar: calendar)
        #expect(months.map(\.month) == [11, 10])
        #expect(months[0] == MonthlyUsage(year: 2026, month: 11, requests: 1, inputTokens: 7, outputTokens: 3, cost: 0))
        #expect(months[1].requests == 2 && months[1].inputTokens == 26_000 && months[1].outputTokens == 1_000)
        // (1,000×4 + 500×20 + 2,000×4×1.25 + 10,000×0.2) / 1M = 0.026 per request
        #expect(abs(months[1].cost - 0.052) < 1e-12)
    }
}
