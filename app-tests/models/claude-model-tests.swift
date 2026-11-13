import FolioAI
import FolioActions
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
        #expect(model.notes.map(\.title) == ["09-08(화) 매칭"])
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
        #expect(ClaudeModel.toolLabel("mcp__folio__action_search") == "액션 찾는 중")
        // `action_run` names its command once that much of the input has streamed in.
        #expect(ClaudeModel.toolLabel("mcp__folio__action_run") == "실행할 액션 고르는 중")
        #expect(ClaudeModel.toolLabel("mcp__folio__action_run", input: #"{"action": "semest"#) == "실행할 액션 고르는 중")
        #expect(ClaudeModel.toolLabel("mcp__folio__action_run", input: #"{"action": "semester add", "inp"#) == "제안 만드는 중: semester add")
        #expect(
            ClaudeModel.toolLabel("mcp__folio__action_run", input: #"{"action":"exam_scope_taught"}"#) == "제안 만드는 중: exam scope --taught")
        #expect(ClaudeModel.toolLabel("mcp__folio__action_run", input: #"{"action":"folio settings show"}"#) == "읽는 중: settings show")
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
        #expect(page.contains(#"<div class="proposal"><div class="row"><span>"#))
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

    /// A figure is approved on what it looks like, so its card shows it as the note would, before anything is written.
    @Test func aProposedFigureShowsBeforeItIsWritten() throws {
        let workspace = try fixtureWorkspace()
        let model = ClaudeModel(workspace: workspace)
        let course = try #require(workspace.course(graphTheory))
        model.load(course)
        let svg =
            #"<svg xmlns="http://www.w3.org/2000/svg"><style>.a{fill:#222}@media (prefers-color-scheme: dark){.a{fill:#E6E2DB}}</style><rect class="a"/></svg>"#
        let add = ActionProposal(
            command: NoteFigureAdd.command, input: try JSONValue(NoteFigureAdd(course: graphTheory, name: "graph", svg: svg)))
        let line = model.describe(add)
        #expect(line.refusal == nil)
        #expect(line.change == .figure(svg))
        let html = ClaudeModel.figureHTML(svg)
        let images = html.matches(of: /data:image\/svg\+xml;base64,([A-Za-z0-9+\/=]+)/).compactMap { Data(base64Encoded: String($0.1)) }
        #expect(images.map { String(decoding: $0, as: UTF8.self) } == [svg])
        #expect(html.contains("<details class=\"change\" open>"))
        #expect(!FileManager.default.fileExists(atPath: course.store.fileURL(NoteFigure.path("graph.svg")).path))
        let bad = ActionProposal(
            command: NoteFigureAdd.command, input: try JSONValue(NoteFigureAdd(course: graphTheory, name: "g", svg: "<svg/>")))
        #expect(model.describe(bad).refusal != nil)
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

    /// A chat of one answer holding `proposals`, open in the panel.
    func open(_ proposals: [ActionProposal], in model: ClaudeModel) -> ChatMessage {
        var chat = Chat(device: model.workspace.device, at: .now)
        let answer = ChatMessage(role: .assistant, text: "제안했습니다", at: .now, proposals: proposals)
        chat.messages = [ChatMessage(role: .user, text: "질문", at: .now), answer]
        model.replace(StoredDocument(new: chat))
        model.select(chat.id)
        return answer
    }

    /// A rewrite shows the lines it changes against the note on disk, an edit each replacement and what it appends;
    /// both escaped, since a note may hold HTML.
    @Test func noteProposalsShowWhatTheyChange() throws {
        let workspace = try fixtureWorkspace()
        let model = ClaudeModel(workspace: workspace)
        let course = try #require(workspace.course(graphTheory))
        model.load(course)
        let note = try #require(model.notes.first)
        let path = course.store.notePath(of: note.url)
        let old = try course.store.read(note)
        let write = ActionProposal(
            command: NoteWrite.command, input: try JSONValue(NoteWrite(course: graphTheory, note: path, text: old + "<b>새 줄</b>\n")))
        let edit = ActionProposal(
            command: NoteEdit.command,
            input: try JSONValue(
                NoteEdit(
                    course: graphTheory, note: path, replacements: [.init(old: "옛 글", new: "새 글\n둘째 줄")], append: "덧붙임")))

        guard case .rewrite(let lines)? = model.describe(write).change else { Issue.record("no diff"); return }
        #expect(lines.last == .added("<b>새 줄</b>"))
        #expect(!lines.contains { if case .removed = $0 { true } else { false } })
        #expect(model.describe(edit).change == .edit([.init(old: "옛 글", new: "새 글\n둘째 줄")], append: "덧붙임"))

        _ = open([write, edit], in: model)
        let page = ClaudeModel.html(try #require(model.chat), describe: model.describe)
        #expect(page.contains(#"<details class="change"><summary>바뀌는 내용 +1 -0</summary>"#))
        #expect(page.contains(#"<div class="l add">+ &lt;b&gt;새 줄&lt;/b&gt;</div>"#))
        #expect(!page.contains("<b>새 줄</b>"))
        #expect(page.contains(#"<summary>바뀌는 내용 +3 -1</summary>"#))
        #expect(page.contains(#"<div class="l del">- 옛 글</div><div class="l add">+ 새 글</div><div class="l add">+ 둘째 줄</div>"#))
        #expect(page.contains("끝에 덧붙임"))
        // Applied, the line no longer offers a change to read.
        var applied = write
        applied.applied = true
        #expect(model.describe(applied).change == nil)
    }

    /// One question for every proposal that asks, and nothing written while one of them would be refused.
    @Test func applyingAllAsksOnceAndWritesNothingWhenOneIsRefused() throws {
        let workspace = try fixtureWorkspace()
        let model = ClaudeModel(workspace: workspace)
        let (a, b, twin) = (UUID(), UUID(), UUID())
        workspace.run(ExamAdd(id: a, course: graphTheory, title: "퀴즈 1"))
        workspace.run(ExamAdd(id: b, course: graphTheory, title: "퀴즈 2"))
        let course = try #require(workspace.course(graphTheory))
        model.load(course)
        func proposal(_ action: some Action) throws -> ActionProposal {
            ActionProposal(command: type(of: action).command, input: try JSONValue(action))
        }

        // Each alone would go through; the second can't once the first has made the exam.
        let refused = open(
            [
                try proposal(ExamAdd(id: twin, course: graphTheory, title: "새 시험")),
                try proposal(ExamAdd(id: twin, course: graphTheory, title: "또")),
            ], in: model)
        #expect(ClaudeModel.html(try #require(model.chat), describe: model.describe).contains("folio://action/applyall/\(refused.id)"))
        model.applyAll(message: refused.id, course: course, confirmed: false)
        #expect(model.confirming == nil)
        #expect(workspace.error?.hasPrefix("2번째 제안이 막혀") == true)
        #expect(workspace.course(graphTheory)?.file.exams.count == 2)
        #expect(model.chat?.messages[1].proposals?.allSatisfy { $0.applied != true } == true)

        let removes = open(
            [
                try proposal(ExamRemove(course: graphTheory, exam: a)), try proposal(ExamRemove(course: graphTheory, exam: b)),
                try proposal(ExamAdd(course: graphTheory, title: "기말")),
            ], in: model)
        model.applyAll(message: removes.id, course: course, confirmed: false)
        let question = try #require(model.confirming)
        #expect(question.index == nil && question.question.split(separator: "\n").count == 2)
        #expect(question.question.contains("퀴즈 1") && question.question.contains("퀴즈 2"))
        #expect(workspace.course(graphTheory)?.file.exams.count == 2)
        model.confirm(question, course: course)
        #expect(workspace.course(graphTheory)?.file.exams.map(\.title) == ["기말"])
        #expect(model.chat?.messages[1].proposals?.allSatisfy { $0.applied == true } == true)
        #expect(
            try course.store.chats().first { $0.model.id == model.chatID }?.model.messages[1].proposals?.allSatisfy { $0.applied == true }
                == true)
        #expect(model.status == "제안 3개를 적용했습니다")
    }

    /// Two changes to one exam in one answer run in the answer's order, so the last one stands.
    @Test func applyingAllRunsInTheAnswersOrder() throws {
        let workspace = try fixtureWorkspace()
        let model = ClaudeModel(workspace: workspace)
        let exam = UUID()
        workspace.run(ExamAdd(id: exam, course: graphTheory, title: "퀴즈"))
        let course = try #require(workspace.course(graphTheory))
        model.load(course)
        let first = ActionProposal(
            command: ExamSet.command, input: try JSONValue(ExamSet(course: graphTheory, exam: exam, title: .set("첫째"))))
        let second = ActionProposal(
            command: ExamSet.command, input: try JSONValue(ExamSet(course: graphTheory, exam: exam, title: .set("둘째"))))
        let answer = open([first, second], in: model)
        model.applyAll(message: answer.id, course: course, confirmed: false)
        #expect(workspace.course(graphTheory)?.file.exams.map(\.title) == ["둘째"])
    }

    /// A later answer's proposal for the same note replaces the earlier one, which then offers nothing.
    @Test func aSupersededProposalIsNotOffered() throws {
        let workspace = try fixtureWorkspace()
        let model = ClaudeModel(workspace: workspace)
        let course = try #require(workspace.course(graphTheory))
        model.load(course)
        let path = course.store.notePath(of: try #require(model.notes.first).url)
        func write(_ text: String) throws -> ActionProposal {
            ActionProposal(command: NoteWrite.command, input: try JSONValue(NoteWrite(course: graphTheory, note: path, text: text)))
        }
        let older = ChatMessage(
            role: .assistant, text: "1", at: .now,
            proposals: [
                try write("첫 안"), ActionProposal(command: ExamAdd.command, input: try JSONValue(ExamAdd(course: graphTheory, title: "퀴즈"))),
            ])
        let newer = ChatMessage(role: .assistant, text: "2", at: .now, proposals: [try write("둘째 안")])
        let chat = Chat(device: workspace.device, at: .now, messages: [older, newer])
        let superseded = model.superseded(chat)
        #expect(superseded == [ProposalRef(message: older.id, index: 0)])
        #expect(ClaudeModel.offered(older, superseded: superseded, describe: model.describe) == [1])
        let page = ClaudeModel.html(chat, superseded: superseded, describe: model.describe)
        #expect(page.contains("대체됨"))
        #expect(!page.contains("folio://action/apply/\(older.id)/0"))
        #expect(page.contains("folio://action/apply/\(newer.id)/0"))
        #expect(!page.contains("folio://action/applyall/"))
    }

    /// #90: a proposal the panel's server made on top of an earlier one of the answer waits until that one is applied.
    @Test func aProposalOnAnEarlierOneWaitsForIt() throws {
        let workspace = try fixtureWorkspace()
        let model = ClaudeModel(workspace: workspace)
        let course = try #require(workspace.course(graphTheory))
        model.load(course)
        let exam = UUID()
        let add = ActionProposal(command: ExamAdd.command, input: try JSONValue(ExamAdd(id: exam, course: graphTheory, title: "퀴즈")))
        let rename = ActionProposal(
            command: ExamSet.command, input: try JSONValue(ExamSet(course: graphTheory, exam: exam, title: .set("쪽지 시험"))), after: [0])
        let answer = open([add, rename], in: model)
        var page = ClaudeModel.html(try #require(model.chat), describe: model.describe)
        #expect(page.contains("앞의 1번 제안"))
        #expect(page.contains("folio://action/apply/\(answer.id)/0"))
        #expect(!page.contains("folio://action/apply/\(answer.id)/1"))
        #expect(ClaudeModel.offered(answer, superseded: [], describe: model.describe) == [0, 1])

        model.apply(message: answer.id, index: 1, course: course, confirmed: false)
        #expect(workspace.error?.contains("1번") == true)
        #expect(workspace.course(graphTheory)?.file.exams.isEmpty == true)

        model.apply(message: answer.id, index: 0, course: course, confirmed: false)
        page = ClaudeModel.html(try #require(model.chat), describe: model.describe)
        #expect(page.contains("folio://action/apply/\(answer.id)/1"))
        model.apply(message: answer.id, index: 1, course: course, confirmed: false)
        #expect(workspace.course(graphTheory)?.file.exams.map(\.title) == ["쪽지 시험"])
    }

    /// One it builds on that can't be applied any more blocks it too, and neither is offered to apply all.
    @Test func aProposalOnARefusedOneIsBlocked() throws {
        let workspace = try fixtureWorkspace()
        let model = ClaudeModel(workspace: workspace)
        let exam = UUID()
        workspace.run(ExamAdd(id: exam, course: graphTheory, title: "퀴즈"))
        let course = try #require(workspace.course(graphTheory))
        model.load(course)
        // The id is taken, so the first is refused for a reason of its own.
        let add = ActionProposal(command: ExamAdd.command, input: try JSONValue(ExamAdd(id: exam, course: graphTheory, title: "또 퀴즈")))
        let rename = ActionProposal(
            command: ExamSet.command, input: try JSONValue(ExamSet(course: graphTheory, exam: UUID(), title: .set("x"))), after: [0])
        let answer = open([add, rename], in: model)
        let page = ClaudeModel.html(try #require(model.chat), describe: model.describe)
        #expect(page.contains("적용할 수 없어 함께 막혔습니다"))
        #expect(ClaudeModel.offered(answer, superseded: [], describe: model.describe).isEmpty)
    }

    /// An edit of the note the answer makes first: a plain dry run can't see the note, the staged check can.
    @Test func applyingAllRunsAnEditOfANoteMadeBeforeIt() throws {
        let workspace = try fixtureWorkspace()
        let model = ClaudeModel(workspace: workspace)
        let course = try #require(workspace.course(graphTheory))
        model.load(course)
        let note = UUID()
        let add = ActionProposal(
            command: NoteAdd.command, input: try JSONValue(NoteAdd(id: note, course: graphTheory, title: "증명 모음", body: "첫 줄\n")))
        let edit = ActionProposal(
            command: NoteEdit.command,
            input: try JSONValue(NoteEdit(course: graphTheory, note: "Notes/증명 모음.md", replacements: [], append: "덧붙인 줄")), after: [0])
        let answer = open([add, edit], in: model)
        #expect(workspace.refusal([try #require(workspace.action(add)), try #require(workspace.action(edit))]) != nil)
        #expect(ClaudeModel.offered(answer, superseded: [], describe: model.describe) == [0, 1])
        model.applyAll(message: answer.id, course: course, confirmed: false)
        #expect(model.chat?.messages[1].proposals?.allSatisfy { $0.applied == true } == true, "\(workspace.error ?? "")")
        let store = try #require(workspace.course(graphTheory)).store
        let text = try store.read(try #require(try store.note(id: note)))
        #expect(text.contains("첫 줄") && text.contains("덧붙인 줄"), "\(text)")
    }

    /// The page is drawn twice a second while an answer is written; its proposals' dry runs wait for the folder to change.
    @Test func proposalLinesAreWorkedOutOncePerFolderChange() throws {
        let workspace = try fixtureWorkspace()
        let model = ClaudeModel(workspace: workspace)
        let course = try #require(workspace.course(graphTheory))
        model.load(course)
        _ = open([ActionProposal(command: ExamAdd.command, input: try JSONValue(ExamAdd(course: graphTheory, title: "퀴즈")))], in: model)
        let chat = try #require(model.chat)
        _ = model.page(chat, cards: true)
        _ = model.page(chat, cards: true)
        #expect(model.described == 1)
        workspace.run(UnitAdd(course: graphTheory, title: "매칭"))
        _ = model.page(chat, cards: true)
        #expect(model.described == 2)
    }

    /// The card goes to the unit on screen, then the open note's unit, and only without either to the first unit.
    @Test func aCardFromAnAnswerGoesToTheUnitInView() throws {
        let workspace = try fixtureWorkspace()
        let model = ClaudeModel(workspace: workspace)
        let (first, second) = (UUID(), UUID())
        workspace.run(UnitAdd(id: first, course: graphTheory, title: "그래프"))
        workspace.run(UnitAdd(id: second, course: graphTheory, title: "매칭"))
        let note = try #require(workspace.run(NoteAdd(course: graphTheory, title: "매칭 정리", kind: .unit, units: [second]))?.made)
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
        let first = requests.withLock {
            $0.append(request); return $0.count == 1
        }
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
