import FolioActions
import FolioAI
import FolioDomain
import FolioStorage
import Foundation
import Synchronization
import Testing
@testable import Folio

@MainActor
struct ClaudeModelTests {
    @Test func aContextItemAddedAgainMovesToTheEndAndComesBackFromRemoved() throws {
        let model = ClaudeModel(workspace: try fixtureWorkspace())
        let a = ContextBuilder.material(path: "Lectures/a.pdf", text: "a"), b = ContextBuilder.material(path: "Lectures/b.pdf", text: "b")
        model.add(a)
        model.add(b)
        model.remove(a)
        model.add(a)
        #expect(model.added.map(\.id) == [b.id, a.id])
        #expect(model.removed.isEmpty)
        model.add(nil)
        #expect(model.added.count == 2)
    }

    @Test func switchingChatsClearsTheLastMessageAndRetry() throws {
        let model = ClaudeModel(workspace: try fixtureWorkspace())
        model.status = "복사했습니다"
        model.failed = "질문"
        model.select(nil)
        #expect(model.status == nil && model.failed == nil && model.chatID == nil)
        #expect(model.chatOptions.map(\.title) == ["새 대화"])
    }

    @Test func loadingACourseReadsItsChatsAndNotes() throws {
        let workspace = try fixtureWorkspace()
        let model = ClaudeModel(workspace: workspace)
        let course = try #require(workspace.course(graphTheory))
        model.load(course)
        #expect(model.chats.isEmpty && model.chatID == nil)
        #expect(model.notes.map(\.title) == ["2주차-1"])
        #expect(model.addOptions(course).first?.section == "노트")
    }

    /// The open note goes as it is on disk when the question is sent, not as it was when it opened. Stopping leaves no
    /// half chat and keeps the question for the resend button, which then answers as usual.
    @Test func theOpenNoteIsReadWhenSentAndAStoppedQuestionCanBeSentAgain() async throws {
        let workspace = try fixtureWorkspace()
        let provider = StoppableProvider()
        let model = ClaudeModel(workspace: workspace, client: { _ in ClaudeClient(provider: provider) })
        let course = try #require(workspace.course(graphTheory))
        model.load(course)
        let note = try #require(model.notes.first)
        let id = try #require(note.meta.id)
        model.loadOpenNote(id, course: course)
        try (String(contentsOf: note.url, encoding: .utf8) + "\n새로 쓴 줄\n").write(to: note.url, atomically: true, encoding: .utf8)

        model.send("질문", course: course)
        try await until { model.tool != nil }
        let sent = try #require(provider.requests.withLock { $0.first })
        let text = sent.messages.last?.content.compactMap { if case .text(let t, _) = $0 { t } else { nil } }.joined() ?? ""
        #expect(text.contains("새로 쓴 줄"))
        #expect(text.contains("경로: Notes/\(note.url.lastPathComponent)\nID: \(id.uuidString)"))
        // The text before the tool call belonged to an earlier message, so only the tool shows.
        #expect(model.partial == nil && model.progress == "읽는 중: note show")

        model.stop()
        try await until { !model.sending }
        #expect(model.failed == "질문" && model.status == "멈췄습니다" && !model.statusIsError)
        #expect(model.chats.isEmpty && model.chatID == nil)
        #expect(try course.store.chats().isEmpty)

        model.send(try #require(model.failed), course: course)
        try await until { !model.sending }
        #expect(model.failed == nil && model.status == nil)
        #expect(model.chat?.messages.map(\.text) == ["질문", "답"])
        #expect(try course.store.chats().first?.model.messages.count == 2)
    }

    @Test func toolCallsSayWhetherTheyReadOrPropose() {
        #expect(ClaudeModel.toolLabel("mcp__folio__note_show") == "읽는 중: note show")
        #expect(ClaudeModel.toolLabel("mcp__folio__note_add") == "제안 만드는 중: note add")
        #expect(ClaudeModel.toolLabel("mcp__folio__exam_scope_taught") == "제안 만드는 중: exam scope --taught")
    }

    func until(_ condition: () -> Bool) async throws {
        let clock = ContinuousClock(), start = clock.now
        while !condition() {
            guard clock.now - start < .seconds(10) else { Issue.record("timed out"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func anAnswerIsNamedByItsFirstHeading() {
        #expect(ClaudeModel.noteTitle("intro\n# 매칭 정리 \n## 더") == "매칭 정리")
        #expect(ClaudeModel.noteTitle("## 둘째 수준만") == nil)
    }

    @Test func errorsReadAsSentences() {
        #expect(ClaudeModel.message(for: ClaudeError.http(status: 401, body: "")) == "인증에 실패했습니다. API 키나 Claude Code 로그인을 확인하세요.")
        #expect(ClaudeModel.message(for: ClaudeError.http(status: 500, body: "")) == "요청이 실패했습니다 (HTTP 500).")
        #expect(ClaudeModel.message(for: ClaudeError.http(status: 0, body: "cli says no")) == "요청이 실패했습니다: cli says no")
    }

    @Test func withoutUnitsTheCardLinkIsOff() {
        var chat = Chat(device: UUID(), at: .now)
        chat.messages = [ChatMessage(role: .user, text: "질문", at: .now), ChatMessage(role: .assistant, text: "답", at: .now)]
        #expect(ClaudeModel.html(chat, cards: false).contains(#"<span class="off""#))
        #expect(ClaudeModel.html(chat, cards: true).contains("folio://action/card/"))
        #expect(ClaudeModel.html(chat, partial: "쓰는 중").contains("쓰는 중"))
        #expect(!ClaudeModel.html(chat).contains("SQL("))
    }

    /// A proposal runs only when the user applies it, once, and the chat file remembers it was applied.
    @Test func aProposalAppliesOnceAndARemovalAsksFirst() throws {
        let workspace = try fixtureWorkspace()
        let model = ClaudeModel(workspace: workspace)
        let course = try #require(workspace.course(graphTheory))
        model.load(course)
        let exam = UUID()
        let add = ActionProposal(command: ExamAdd.command, input: try JSONValue(ExamAdd(id: exam, course: graphTheory, title: "제안 퀴즈")))
        let remove = ActionProposal(command: ExamRemove.command, input: try JSONValue(ExamRemove(course: graphTheory, exam: exam)))
        #expect(model.describe(add).refusal == nil)
        var chat = Chat(device: workspace.device, at: .now)
        let answer = ChatMessage(role: .assistant, text: "제안했습니다", at: .now, proposals: [add, remove])
        chat.messages = [answer]
        model.replace(StoredDocument(new: chat))
        model.select(chat.id)
        let page = ClaudeModel.html(chat, describe: model.describe)
        #expect(page.contains(#"<div class="proposal"><span>"#))
        #expect(page.contains(#"<a href="folio://action/apply/\#(answer.id)/0">"#))
        #expect(!page.contains("SQL("))

        model.apply(message: answer.id, index: 0, course: course, confirmed: false)
        model.apply(message: answer.id, index: 0, course: course, confirmed: false)
        #expect(workspace.course(graphTheory)?.file.exams.map(\.title) == ["제안 퀴즈"])
        #expect(model.chat?.messages[0].proposals?[0].applied == true)
        #expect(try course.store.chats().first?.model.messages[0].proposals?[0].applied == true)

        model.apply(message: answer.id, index: 1, course: course, confirmed: false)
        #expect(model.confirming?.index == 1)
        #expect(workspace.course(graphTheory)?.file.exams.count == 1)
        model.apply(message: answer.id, index: 1, course: course, confirmed: true)
        #expect(workspace.course(graphTheory)?.file.exams.isEmpty == true)
    }

    /// A proposal that fails when applied keeps why, in the chat file and in its line, instead of only a passing banner.
    @Test func aFailedProposalKeepsItsReason() throws {
        let workspace = try fixtureWorkspace()
        let model = ClaudeModel(workspace: workspace)
        let course = try #require(workspace.course(graphTheory))
        model.load(course)
        let gone = ActionProposal(command: ExamRemove.command, input: try JSONValue(ExamRemove(course: graphTheory, exam: UUID())))
        var chat = Chat(device: workspace.device, at: .now)
        let answer = ChatMessage(role: .assistant, text: "제안했습니다", at: .now, proposals: [gone])
        chat.messages = [answer]
        model.replace(StoredDocument(new: chat))
        model.select(chat.id)

        model.apply(message: answer.id, index: 0, course: course, confirmed: true)
        let failure = try #require(model.chat?.messages[0].proposals?[0].failure)
        #expect(model.chat?.messages[0].proposals?[0].applied != true)
        #expect(try course.store.chats().first?.model.messages[0].proposals?[0].failure == failure)
        let page = ClaudeModel.html(try #require(model.chat), describe: model.describe)
        #expect(page.contains(#"<span class="why">"#))
    }

    /// The note list and a unit's notes re-read on the revision, so an answer saved as a note must bump it like the new-note sheet does.
    @Test func anAnswerSavedAsANoteOrAnAppliedNoteProposalShowsInTheNoteLists() throws {
        let workspace = try fixtureWorkspace()
        let model = ClaudeModel(workspace: workspace)
        let course = try #require(workspace.course(graphTheory))
        model.load(course)
        var revision = workspace.notesRevision
        #expect(model.createNote(title: "답변", body: "본문", course: course) != nil)
        #expect(workspace.notesRevision > revision)

        revision = workspace.notesRevision
        let add = ActionProposal(command: NoteAdd.command, input: try JSONValue(NoteAdd(course: graphTheory, title: "제안 노트")))
        var chat = Chat(device: workspace.device, at: .now)
        let answer = ChatMessage(role: .assistant, text: "제안했습니다", at: .now, proposals: [add])
        chat.messages = [answer]
        model.replace(StoredDocument(new: chat))
        model.select(chat.id)
        model.apply(message: answer.id, index: 0, course: course, confirmed: false)
        #expect(workspace.notesRevision > revision)
    }

    /// The card goes to the unit on screen, then the open note's unit, and only without either to the first unit.
    @Test func aCardFromAnAnswerGoesToTheUnitInView() throws {
        let workspace = try fixtureWorkspace()
        let model = ClaudeModel(workspace: workspace)
        let (first, second) = (UUID(), UUID())
        workspace.run(UnitAdd(id: first, course: graphTheory, title: "그래프"))
        workspace.run(UnitAdd(id: second, course: graphTheory, title: "매칭"))
        let note = try #require(workspace.run(NoteAdd(course: graphTheory, title: "매칭 정리", kind: .topic, units: [second]))?.made)
        let course = try #require(workspace.course(graphTheory))
        model.load(course)
        var chat = Chat(device: workspace.device, at: .now)
        let answer = ChatMessage(role: .assistant, text: "답", at: .now)
        chat.messages = [ChatMessage(role: .user, text: "매칭이란?", at: .now), answer]
        model.replace(StoredDocument(new: chat))
        model.select(chat.id)
        let url = try #require(URL(string: "folio://action/card/\(answer.id)"))
        func draftUnit(note: UUID?, unit: UUID?) -> UUID? {
            model.cardDraft = nil
            model.handle(url, course: course, openNote: note, openUnit: unit, insertIntoNote: { _ in }, showNote: { _ in })
            return model.cardDraft?.unitId
        }
        #expect(draftUnit(note: nil, unit: second) == second)
        #expect(draftUnit(note: note, unit: nil) == second)
        #expect(draftUnit(note: nil, unit: nil) == first)
        #expect(model.cardDraft?.prompt == "매칭이란?")
    }
}

/// The first answer reads with a tool, then runs until stopped; later ones answer at once.
final class StoppableProvider: ClaudeProvider {
    let requests = Mutex<[MessagesRequest]>([])

    func send(_ request: MessagesRequest) async throws -> MessagesResponse {
        try await send(request) { _ in }
    }

    func send(_ request: MessagesRequest, onEvent: @escaping @Sendable (StreamEvent) -> Void) async throws -> MessagesResponse {
        let first = requests.withLock { $0.append(request); return $0.count == 1 }
        if first {
            let events: [StreamEvent] = [.turn, .text("Look at the note."), .tool("mcp__folio__note_show"), .turn]
            events.forEach(onEvent)
            try await Task.sleep(for: .seconds(60))
        }
        onEvent(.turn)
        onEvent(.text("답"))
        return FakeProvider.reply("답")
    }
}
