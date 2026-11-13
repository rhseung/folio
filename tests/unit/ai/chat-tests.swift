import FolioDomain
import Foundation
import Testing

@testable import FolioAI

struct ChatTests {
    let device = UUID(), now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func panelContextKeepsSummaryAndRulesAndHonorsRemovals() {
        let file = CourseFile(course: Course(device: device, at: now, title: "선형대수학"))
        let noteID = UUID()
        let open = ContextBuilder.note(id: noteID, title: "3주차", path: "Notes/3주차.md", body: "고유값", open: true)
        let added = [
            ContextBuilder.note(id: noteID, title: "3주차", path: "Notes/3주차.md", body: "고유값", open: false),
            ContextBuilder.material(path: "Lectures/03_eigen.pdf", text: "Eigenvalues"),
        ]
        let items = ContextBuilder.chatItems(course: file, rules: "정의는 전제부터", openNote: open, added: added, removed: [], now: now)
        #expect(items.map(\.id) == ["course:\(file.course.id)", "rules", "note:\(noteID)", "material:Lectures/03_eigen.pdf"])
        #expect(items[2].tier == .focus)

        let fewer = ContextBuilder.chatItems(
            course: file, rules: "r", openNote: open, added: added, removed: ["material:Lectures/03_eigen.pdf"], now: now)
        #expect(fewer.map(\.id).contains("material:Lectures/03_eigen.pdf") == false)
        #expect(ContextBuilder.chatItems(course: file, rules: "r", openNote: nil, added: [], removed: [], now: now).count == 2)
    }

    /// One panel for the window's panes: it says which pane is focused before the notes they show, and a folded
    /// pane only by its address.
    @Test func thePanesComeFocusedFirstBeforeTheirNotes() throws {
        let file = CourseFile(course: Course(device: device, at: now, title: "그래프 이론"))
        let lecture = UUID(), note = UUID(), quiz = UUID()
        let item = try #require(
            ContextBuilder.panes([
                .init(address: "folio://material/\(lecture)", shows: "05_Matchings.pdf", focused: false),
                .init(address: "folio://note/\(note)", shows: "11-05(목) Matchings", focused: true),
                .init(address: "folio://course/\(quiz)/quiz", shows: nil, focused: false),
            ]))
        let lines = item.text.split(separator: "\n").dropFirst().map(String.init)
        #expect(
            lines == [
                "- [초점] 11-05(목) Matchings: folio://note/\(note)", "- 05_Matchings.pdf: folio://material/\(lecture)",
                "- (접힘) folio://course/\(quiz)/quiz",
            ])
        let open = ContextBuilder.note(id: note, title: "11-05(목) Matchings", path: "Notes/a.md", body: "매칭", open: true)
        let other = ContextBuilder.note(id: UUID(), title: "10-29(목) 정리", path: "Notes/b.md", body: "정리", open: true)
        let items = ContextBuilder.chatItems(
            course: file, rules: "r", panes: item, openNote: open, alsoOpen: [other, open], added: [],
            removed: [], now: now)
        #expect(items.map(\.id) == ["course:\(file.course.id)", "rules", "panes", open.id, other.id])
        // A lone pane is what its note already says.
        #expect(ContextBuilder.panes([.init(address: "folio://note/\(note)", shows: "노트", focused: true)]) == nil)
    }

    @Test func aPageAskedAboutIsInFocusWithItsPicture() {
        let id = UUID()
        let image = ContextItem.Image(name: "05_Matchings.pdf p3.jpg", data: Data([0xFF, 0xD8]))
        let page = ContextBuilder.materialPage(id: id, path: "Lectures/05_Matchings.pdf", page: 3, text: "Hall's theorem", image: image)
        #expect(page.id == "material:Lectures/05_Matchings.pdf#page=3" && page.tier == .focus)
        #expect(page.text.contains("ID: \(id.uuidString)") && page.text.contains("쪽: 3") && page.text.hasSuffix("Hall's theorem"))
        #expect(page.images == [image])
        // Another page of the same file is another item, so asking about both keeps both.
        #expect(ContextBuilder.materialPage(id: id, path: "Lectures/05_Matchings.pdf", page: 4, text: "", image: nil).id != page.id)
    }

    @Test func replySendsHistoryAndPutsContextBeforeTheNewQuestion() async throws {
        let fake = FakeProvider(responses: [FakeProvider.reply("$\\lambda$ 는 고유값입니다")])
        let file = CourseFile(course: Course(device: device, at: now, title: "선형대수학"))
        let noteID = UUID()
        let open = ContextBuilder.note(id: noteID, title: "3주차", path: "Notes/09-15(월) 고유값 정리.md", body: "본문", open: true)
        let items = ContextBuilder.chatItems(course: file, rules: "규칙", openNote: open, added: [], removed: [], now: now)
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
        // The path and ID tell Claude which file is open, which the title alone left it to guess.
        #expect(
            r.messages[2].content == [
                .text("<열린 노트: 3주차>\n경로: Notes/09-15(월) 고유값 정리.md\nID: \(noteID.uuidString)\n\n본문\n</열린 노트: 3주차>"),
                .text("고유값이 뭐야?"),
            ])
        guard case .text(let instructions, _)? = r.system?.first else { Issue.record("no instructions"); return }
        #expect(instructions.contains("Put the whole answer in your final message"))
        guard case .text(let stable, let cache)? = r.system?.last else { Issue.record("no system"); return }
        #expect(cache && stable.contains("과목: 선형대수학") && stable.contains("규칙"))
    }

    /// The next question carries what became of each proposed change, so Claude doesn't have to guess.
    @Test func historyTellsWhatBecameOfEachProposal() async throws {
        let long = String(repeating: "가", count: 500)
        let proposals = [
            ActionProposal(command: "note write", input: .object(["note": .string("Notes/a.md"), "text": .string(long)])),
            ActionProposal(command: "note link", input: .object(["note": .string("n")]), applied: true),
            ActionProposal(command: "exam rm", input: .object(["exam": .string("e")]), failure: "시험 'e'을(를) 찾을 수 없습니다"),
        ]
        let fake = FakeProvider(responses: [FakeProvider.reply("답")])
        let chat = Chat(
            device: device, at: now,
            messages: [
                ChatMessage(role: .user, text: "써 줘", at: now),
                ChatMessage(role: .assistant, text: "제안했어요", at: now, proposals: proposals),
                ChatMessage(role: .user, text: "됐어?", at: now),
            ])
        _ = try await ClaudeClient(provider: fake).reply(to: chat, context: ContextBuilder.build([], budgetTokens: 10))
        let r = try #require(await fake.requests.first)
        guard case .text(let sent, _)? = r.messages[1].content.first else { Issue.record("no answer text"); return }
        #expect(sent.hasPrefix("제안했어요\n\n[Changes proposed in this answer]\n"))
        #expect(
            sent.contains(
                "- note write {\"note\":\"Notes/a.md\",\"text\":\"\(String(repeating: "가", count: 80))… (500 characters)\"}: not applied; the user has not approved it"
            ))
        #expect(sent.contains("- note link {\"note\":\"n\"}: applied"))
        #expect(sent.contains("- exam rm {\"exam\":\"e\"}: the user applied it and it failed: 시험 'e'을(를) 찾을 수 없습니다"))
        #expect(!sent.contains(long))
        #expect(ClaudeClient.history(ChatMessage(role: .assistant, text: "그냥 답", at: now)) == "그냥 답")
    }

    /// A proposal a later answer replaced reads as such, so Claude doesn't ask the user to approve the older one.
    @Test func historySaysWhichProposalsWereSuperseded() async throws {
        let first = ActionProposal(
            command: "note write", input: .object(["course": .string("c"), "note": .string("Notes/a.md"), "text": .string("1")]))
        var second = first
        second.input["text"] = .string("2")
        let fake = FakeProvider(responses: [FakeProvider.reply("답")])
        let chat = Chat(
            device: device, at: now,
            messages: [
                ChatMessage(role: .user, text: "써 줘", at: now),
                ChatMessage(role: .assistant, text: "하나", at: now, proposals: [first]),
                ChatMessage(role: .user, text: "다시", at: now),
                ChatMessage(role: .assistant, text: "둘", at: now, proposals: [second]),
                ChatMessage(role: .user, text: "됐어?", at: now),
            ])
        _ = try await ClaudeClient(provider: fake).reply(
            to: chat, context: ContextBuilder.build([], budgetTokens: 10),
            targets: ["note write": ProposalTarget(arguments: ["course", "note"], effect: .replaces(covers: []))])
        let r = try #require(await fake.requests.first)
        func sent(_ i: Int) -> String { if case .text(let t, _)? = r.messages[i].content.first { t } else { "" } }
        #expect(sent(1).hasSuffix(": not applied; superseded by a later proposal"))
        #expect(sent(3).hasSuffix(": not applied; the user has not approved it"))
    }

    @Test func replyNeedsAQuestion() async {
        let chat = Chat(device: device, at: now, messages: [ChatMessage(role: .assistant, text: "a", at: now)])
        await #expect(throws: ClaudeError.self) {
            try await ClaudeClient(provider: FakeProvider(responses: [])).reply(
                to: chat, context: ContextBuilder.build([], budgetTokens: 10))
        }
    }

    @Test func monthlyUsageSumsTokensAndCost() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let oct = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 23))!
        let nov = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 1))!
        let opus = APIUsageEvent(
            task: .chat, model: "claude-opus-5-5",
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
