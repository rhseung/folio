import FolioAI
import FolioActions
import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation
import Observation
import Synchronization

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor @Observable
final class ClaudeModel {
    let workspace: Workspace
    var chats: [StoredDocument<Chat>] = []
    var chatID: UUID?
    var notes: [NoteFile] = []
    var openNoteItem: ContextItem?
    var alsoOpenItems: [ContextItem] = []
    var panes: ContextItem?
    var added: [ContextItem] = []
    var removed: Set<String> = []
    var sending = false
    var status: String?
    var failed: String?
    var partial: String?
    var tool: String?
    var toolInput = ""
    var stopped = false
    // 답하는 도중에 대화를 바꾸면 그 답이 다른 대화 아래에 보이면 안 된다.
    var answering: UUID?
    var openNote: UUID?
    private var answer: Task<Void, Never>?
    private let client: ((LoadedCourse) -> ClaudeClient)?
    var cardDraft: CardDraft?
    var confirming: PendingProposal?

    struct PendingProposal: Identifiable {
        var message: UUID
        var index: Int?
        var question: String
        var id: String { "\(message)/\(index.map(String.init) ?? "all")" }
    }

    init(workspace: Workspace, client: ((LoadedCourse) -> ClaudeClient)? = nil) {
        self.workspace = workspace
        self.client = client
    }

    var hasKey: Bool { client != nil || workspace.claudeReady }

    var progress: String {
        tool.map { Self.toolLabel($0, input: toolInput) } ?? String(localized: partial == nil ? .claudeWaiting : .claudeWriting)
    }

    var statusIsError: Bool { failed != nil && !stopped }

    var chat: Chat? { chats.first { $0.model.id == chatID }?.model }

    func built(_ course: LoadedCourse) -> BuiltContext {
        let items = ContextBuilder.chatItems(
            course: course.file, rules: workspace.settings.noteRules, panes: panes, openNote: openNoteItem,
            alsoOpen: alsoOpenItems, added: added, removed: removed, now: .now)
        return ContextBuilder.build(items, budgetTokens: ContextBuilder.chatBudgetTokens)
    }

    func tokens(_ built: BuiltContext) -> String {
        String(localized: .claudeContextTokens(built.included.map(ContextBuilder.estimate).reduce(0, +).formatted()))
    }

    var chatOptions: [PickOption<UUID?>] {
        [PickOption(id: UUID?.none, title: String(localized: .claudeNewChat))]
            + chats.map { PickOption(id: Optional($0.model.id), title: $0.model.title) }
    }

    func select(_ id: UUID?) {
        chatID = id
        status = nil
        failed = nil
        stopped = false
    }

    func materials(_ course: LoadedCourse) -> [Material] {
        let readable = course.file.materials.filter {
            !$0.isFolder && [.classified, .unclassified].contains($0.status) && CourseStore.canReadContext($0.path)
        }
        return MaterialRole.allCases.flatMap { role in readable.filter { $0.status == .classified && $0.role == role } }
            + readable.filter { $0.status != .classified || $0.role == nil }
    }

    func addOptions(_ course: LoadedCourse) -> [PickOption<UUID>] {
        notes.compactMap { n in n.meta.id.map { PickOption(id: $0, title: n.title, section: String(localized: .claudeAddNotes)) } }
            + materials(course).map { m in
                PickOption(
                    id: m.id, title: (m.path as NSString).lastPathComponent, detail: m.path,
                    section: m.status == .classified
                        ? m.role?.label ?? String(localized: .claudeAddMaterials) : String(localized: .claudeAddUnclassified))
            }
    }

    // MARK: Loading

    func load(_ course: LoadedCourse) {
        chats = (try? course.store.chats()) ?? []
        chatID = chats.first?.model.id
        notes = Self.notes(course)
    }

    func loadOpenNote(_ id: UUID?, alsoOpen: [UUID] = [], course: LoadedCourse) {
        openNote = id
        openNoteItem = id.flatMap { noteContext($0, course: course, open: true) }
        alsoOpenItems = alsoOpen.filter { $0 != id }.compactMap { noteContext($0, course: course, open: true) }
    }

    static func notes(_ course: LoadedCourse) -> [NoteFile] {
        ((try? course.store.notes()) ?? []).filter { $0.meta.id != nil }
    }

    func noteId(titled title: String, course: LoadedCourse) -> UUID? {
        ((try? course.store.notes()) ?? []).linked(title)?.meta.id
    }

    func noteContext(_ id: UUID, course: LoadedCourse, open: Bool) -> ContextItem? {
        guard let note = try? course.store.note(id: id), let text = try? course.store.read(note) else { return nil }
        let body = Frontmatter.split(text).body
        let images = course.store.contextImages(of: note, body: body).map { ContextItem.Image(name: $0.name, data: $0.data) }
        return ContextBuilder.note(
            id: id, title: note.title, path: course.store.notePath(of: note.url), body: body, images: images, open: open)
    }

    func materialContext(_ material: Material, course: LoadedCourse) -> ContextItem? {
        do {
            guard let text = try course.store.contextText(ofMaterial: material.path), !text.isEmpty else {
                workspace.error = String(localized: .claudeMaterialUnreadable)
                return nil
            }
            return ContextBuilder.material(path: material.path, text: text)
        } catch {
            workspace.error = "\(error)"
            return nil
        }
    }

    // MARK: Context

    func addContext(_ id: UUID, course: LoadedCourse) {
        if let m = materials(course).first(where: { $0.id == id }) {
            add(materialContext(m, course: course))
        } else {
            add(noteContext(id, course: course, open: false))
        }
    }

    func add(_ item: ContextItem?) {
        guard let item else { return }
        removed.remove(item.id)
        added.removeAll { $0.id == item.id }
        added.append(item)
    }

    func remove(_ item: ContextItem) { removed.insert(item.id) }

    // MARK: Sending

    func send(_ question: String, course: LoadedCourse) {
        guard hasKey, !sending else { return }
        // 노트는 열 때 읽었고 그 뒤에 고쳤을 가능성이 크므로 디스크에서 다시 읽는다.
        loadOpenNote(openNote, course: course)
        let context = built(course)
        var doc =
            chats.first { $0.model.id == chatID }
            ?? StoredDocument(new: Chat(device: workspace.device, at: .now, title: String(question.prefix(40))))
        doc.model.messages.append(ChatMessage(role: .user, text: question, at: .now, context: context.included.map(\.title)))

        // 실패한 요청이 쓰다 만 대화를 남기지 않도록, 질문은 답이 올 때까지 메모리에만 둔다.
        replace(doc)
        chatID = doc.model.id
        answering = doc.model.id
        sending = true
        status = nil
        failed = nil
        stopped = false
        partial = nil
        tool = nil

        let client = client?(course) ?? workspace.claude(for: course, folioTools: true)
        let asked = doc.model
        let stream = AnswerStream()
        answer = Task {
            var doc = doc
            // 조각마다 갱신하면 그때마다 대화 페이지를 다시 불러오므로, 0.5초마다 보인다.
            let ticker = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    let now = stream.now
                    if partial != now.text { partial = now.text }
                    if tool != now.tool { tool = now.tool }
                    if toolInput != now.toolInput { toolInput = now.toolInput }
                }
            }
            defer { ticker.cancel(); partial = nil; tool = nil; toolInput = "" }

            do {
                let reply = try await client.reply(to: asked, context: context, targets: Actions.targets) { stream.take($0) }
                doc.model.messages.append(ChatMessage(role: .assistant, text: reply.text, at: .now, proposals: reply.proposals))
                doc.model.touch(by: workspace.device, at: .now)
                let saved = doc
                // folio:not-an-action chat history is not an action
                workspace.perform { try course.store.save(saved) }
            } catch {
                doc.model.messages.removeLast()
                failed = question
                // API 프로바이더는 취소된 요청을 `CancellationError`가 아니라 URL 오류로 알린다.
                stopped = Task.isCancelled
                status = stopped ? String(localized: .claudeStatusStopped) : Self.message(for: error)
            }

            if doc.model.messages.isEmpty {
                chats.removeAll { $0.model.id == doc.model.id }
                if chatID == doc.model.id { chatID = nil }
            } else {
                replace(doc)
            }
            answering = nil
            sending = false
            answer = nil
        }
    }

    func stop() { answer?.cancel() }

    func replace(_ doc: StoredDocument<Chat>) {
        chats.removeAll { $0.model.id == doc.model.id }
        chats.insert(doc, at: 0)
    }

    func handle(
        _ url: URL, course: LoadedCourse, openNote: UUID?, openUnit: UUID? = nil, insertIntoNote: (String) -> Void, showNote: (UUID) -> Void
    ) {
        let parts = url.pathComponents
        guard parts.count >= 3, let id = UUID(uuidString: parts[2]),
            let message = chat?.messages.first(where: { $0.id == id })
        else { return }

        switch parts[1] {
        case "apply":
            guard parts.count == 4, let index = Int(parts[3]) else { break }
            apply(message: id, index: index, course: course, confirmed: false)
        case "applyall":
            applyAll(message: id, course: course, confirmed: false)
        case "copy":
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message.text, forType: .string)
            #else
            UIPasteboard.general.string = message.text
            #endif
            status = String(localized: .claudeStatusCopied)
        case "newnote":
            if let note = createNote(
                title: Self.noteTitle(message.text) ?? chat?.title ?? Self.answerTitle, body: message.text, course: course)
            {
                notes = Self.notes(course)
                showNote(note)
                status = String(localized: .claudeStatusNewNote)
            }
        case "insert":
            if openNote != nil {
                insertIntoNote(message.text)
                status = String(localized: .claudeStatusInserted)
            } else if let note = createNote(title: chat?.title ?? Self.answerTitle, body: message.text, course: course) {
                notes = Self.notes(course)
                showNote(note)
                status = String(localized: .claudeStatusFreeNote)
            }
        case "card":
            guard let unit = course.file.unitForNewCard(viewing: openUnit, note: openNote), let messages = chat?.messages,
                let i = messages.firstIndex(where: { $0.id == id })
            else { break }
            var draft = CardDraft(unitId: unit)
            draft.prompt = messages[..<i].last { $0.role == .user }?.text ?? ""
            draft.answer = message.text
            cardDraft = draft
        default:
            break
        }
        failed = nil
    }

    // MARK: Proposals

    func page(_ chat: Chat, cards: Bool) -> String {
        Self.html(
            chat, partial: sending && answering == chatID ? partial : nil, cards: cards, superseded: superseded(chat), describe: describe)
    }

    func superseded(_ chat: Chat) -> Set<ProposalRef> { chat.supersededProposals(targets: Actions.targets) }

    // 줄마다 dry run을 돌리고, 답을 쓰는 동안 페이지를 1초에 두 번 다시 그린다. 그래서 폴더가 바뀔 때까지 계산한 줄을
    // 다시 쓴다.
    func describe(_ proposal: ActionProposal) -> ProposalLine {
        if linesRevision != workspace.dataRevision {
            lines = [:]
            linesRevision = workspace.dataRevision
        }
        if let line = lines[proposal] { return line }

        described += 1
        let line: ProposalLine
        if let action = workspace.action(proposal) {
            let pending = proposal.applied != true
            line = ProposalLine(
                text: workspace.summary(action), refusal: pending ? workspace.refusal(action) : nil,
                change: pending ? change(proposal) : nil)
        } else {
            line = ProposalLine(text: proposal.command, refusal: String(localized: .claudeProposalUnknown))
        }
        lines[proposal] = line
        return line
    }

    @ObservationIgnored private var lines: [ActionProposal: ProposalLine] = [:]
    @ObservationIgnored private var linesRevision = -1
    @ObservationIgnored private(set) var described = 0

    // 액션의 필드는 FolioActions 안에서만 보이므로 제안의 입력에서 읽는다.
    func change(_ proposal: ActionProposal) -> ProposalLine.Change? {
        func string(_ key: String) -> String? { if case .string(let s)? = proposal.input[key] { s } else { nil } }
        switch proposal.command {
        case NoteWrite.command:
            guard let text = string("text"), let course = string("course").flatMap(UUID.init(uuidString:)).flatMap(workspace.course),
                let path = string("note"), let note = course.store.note(at: path, in: course.file),
                let old = try? course.store.read(note)
            else { return nil }
            return .rewrite(TextDiff.lines(from: old, to: text))
        case NoteEdit.command:
            let replacements =
                proposal.input["replacements"].flatMap {
                    try? JSONDecoder().decode([NoteEdit.Replacement].self, from: JSONEncoder().encode($0))
                } ?? []
            return .edit(replacements, append: string("append").flatMap { $0.isEmpty ? nil : $0 })
        case NoteFigureAdd.command, NoteFigureWrite.command:
            return string("svg").map(ProposalLine.Change.figure)
        default:
            return nil
        }
    }

    static func offered(_ message: ChatMessage, superseded: Set<ProposalRef>, describe: (ActionProposal) -> ProposalLine) -> [Int] {
        var offered: [Int] = []
        for (i, p) in (message.proposals ?? []).enumerated()
        where p.applied != true && !superseded.contains(ProposalRef(message: message.id, index: i)) {
            switch waiting(message, i, superseded: superseded, describe: describe) {
            case nil: if describe(p).refusal == nil { offered.append(i) }
            case .earlier(let before)?: if before.allSatisfy(offered.contains) { offered.append(i) }
            case .blocked?: break
            }
        }
        return offered
    }

    static func waiting(
        _ message: ChatMessage, _ index: Int, superseded: Set<ProposalRef>,
        describe: (ActionProposal) -> ProposalLine
    ) -> ChatMessage.Waiting? {
        let proposals = message.proposals ?? []
        return message.waiting(index) { j in
            superseded.contains(ProposalRef(message: message.id, index: j)) || describe(proposals[j]).refusal != nil
        }
    }

    static func reason(_ waiting: ChatMessage.Waiting) -> String {
        switch waiting {
        case .earlier(let before): String(localized: .claudeProposalWaiting(before.map { String($0 + 1) }.joined(separator: ", ")))
        case .blocked(let before): String(localized: .claudeProposalWaitingBlocked(before.map { String($0 + 1) }.joined(separator: ", ")))
        }
    }

    func confirm(_ pending: PendingProposal, course: LoadedCourse) {
        if let index = pending.index {
            apply(message: pending.message, index: index, course: course, confirmed: true)
        } else {
            applyAll(message: pending.message, course: course, confirmed: true)
        }
    }

    func apply(message: UUID, index: Int, course: LoadedCourse, confirmed: Bool) {
        guard var doc = chats.first(where: { $0.model.id == chatID }),
            let m = doc.model.messages.firstIndex(where: { $0.id == message }),
            let proposals = doc.model.messages[m].proposals, proposals.indices.contains(index),
            case let proposal = proposals[index], proposal.applied != true,
            let action = workspace.action(proposal)
        else { return }

        if let waiting = Self.waiting(doc.model.messages[m], index, superseded: superseded(doc.model), describe: describe) {
            workspace.error = Self.reason(waiting)
            return
        }
        if !confirmed, let question = workspace.confirmation(action) {
            confirming = PendingProposal(message: message, index: index, question: question)
            return
        }

        if run(action, at: index, of: m, in: &doc) { status = String(localized: .claudeStatusApplied(workspace.summary(action))) }
        save(doc, course: course)
    }

    func applyAll(message: UUID, course: LoadedCourse, confirmed: Bool) {
        guard var doc = chats.first(where: { $0.model.id == chatID }),
            let m = doc.model.messages.firstIndex(where: { $0.id == message })
        else { return }
        let picked = Self.offered(doc.model.messages[m], superseded: superseded(doc.model), describe: describe).compactMap { i in
            doc.model.messages[m].proposals.flatMap { workspace.action($0[i]) }.map { (index: i, action: $0) }
        }
        guard !picked.isEmpty else { return }

        // 일반 dry run은 course.json을 다음 제안으로 넘기지만 파일은 쓰지 않는다. 그래서 답이 먼저 만드는 노트 위에
        // 쌓인 제안은 그 노트가 있는 staged copy에서 다시 검사한다.
        let actions = picked.map(\.action)
        var refusal = workspace.refusal(actions)
        if refusal != nil, picked.contains(where: { doc.model.messages[m].proposals?[$0.index].after?.isEmpty == false }) {
            refusal = workspace.stagedRefusal(actions)
        }
        if let refused = refusal {
            workspace.error = String(localized: .claudeProposalBlocked(picked[refused.index].index + 1, refused.reason))
            return
        }

        var questions: [String] = []
        for p in picked {
            let action = p.action
            if let question = workspace.confirmation(action) { questions.append(question) }
        }
        if !confirmed, !questions.isEmpty {
            confirming = PendingProposal(message: message, index: nil, question: questions.joined(separator: "\n"))
            return
        }

        var applied = 0
        for p in picked {
            guard run(p.action, at: p.index, of: m, in: &doc) else { break }
            applied += 1
        }
        if applied == picked.count { status = String(localized: .claudeStatusAppliedAll(applied)) }
        save(doc, course: course)
    }

    private func run(_ action: any Action, at index: Int, of message: Int, in doc: inout StoredDocument<Chat>) -> Bool {
        do {
            _ = try workspace.runThrowing(action)
            doc.model.messages[message].proposals?[index].applied = true
            doc.model.messages[message].proposals?[index].failure = nil
            return true
        } catch {
            doc.model.messages[message].proposals?[index].failure = "\(error)"
            workspace.error = "\(error)"
            return false
        }
    }

    private func save(_ doc: StoredDocument<Chat>, course: LoadedCourse) {
        var doc = doc
        doc.model.touch(by: workspace.device, at: .now)
        let saved = doc
        // folio:not-an-action chat history is not an action
        workspace.perform { try course.store.save(saved) }
        replace(doc)
    }

    func createNote(title: String, body: String, course: LoadedCourse) -> UUID? {
        workspace.run(NoteAdd(course: course.id, title: title, body: body))?.made
    }

    // MARK: Helpers

    static func toolLabel(_ name: String, input: String = "") -> String {
        let prefix = "mcp__folio__"
        var tool = name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
        if tool == "action_search" { return String(localized: .claudeToolSearching) }
        if tool == "action_run" {
            // 입력은 이름 뒤에 스트림으로 들어오므로, `action` 값이 다 도착한 뒤에 명령을 보인다.
            guard let match = input.firstMatch(of: /"action"\s*:\s*"([^"\\]+)"/) else { return String(localized: .claudeToolChoosing) }
            tool = String(match.1).replacing(/^folio\s+/, with: "")
        }
        // MCP 서버의 이름 규칙을 따른다(folio-cli의 `MCPServer.name`). 앱은 folio-cli를 링크하지 않는다.
        let named = tool.replacing(" --", with: "_").replacing(" ", with: "_")
        if let write = Actions.all.first(where: { $0.command.replacing(" --", with: "_").replacing(" ", with: "_") == named }) {
            return String(localized: .claudeToolProposing(write.command))
        }
        return String(localized: .claudeToolReading(tool.replacing("_", with: " ")))
    }

    static let answerTitle = "Claude 답변"  // strings: data, written into the note file as its title

    static func noteTitle(_ markdown: String) -> String? {
        markdown.split(separator: "\n").first { $0.hasPrefix("# ") }.map { $0.dropFirst(2).trimmingCharacters(in: .whitespaces) }
    }

    nonisolated static func message(for error: any Error) -> String {
        switch error as? ClaudeError {
        case .missingAPIKey: String(localized: .claudeErrorMissingKey)
        case .http(let status, let body):
            status == 401
                ? String(localized: .claudeErrorAuth)
                : status == 0
                    ? String(localized: .claudeErrorFailedBody(String(body.prefix(200)))) : String(localized: .claudeErrorHttp(status))
        case .refused: String(localized: .claudeErrorRefused)
        case .truncated: String(localized: .claudeErrorTruncated)
        case .invalidOutput, nil: String(localized: .claudeErrorFailedBody(error.localizedDescription))
        }
    }

    static func html(
        _ chat: Chat, partial: String? = nil, cards: Bool = true, superseded: Set<ProposalRef> = [],
        describe: (ActionProposal) -> ProposalLine = { ProposalLine(text: $0.command) }
    ) -> String {
        let writing = partial.map { #"<div class="msg assistant">\#(HTMLRenderer.render(answer: $0))</div>"# }
        let card = String(localized: .claudeAnswerCard)
        let messages =
            (writing.map { [$0] } ?? [])
            + chat.messages.reversed().map { m in
                let body = HTMLRenderer.render(answer: m.text)
                switch m.role {
                case .user:
                    return #"<div class="msg user">\#(body)</div>"#
                case .assistant:
                    let cardLink =
                        cards
                        ? #"<a href="folio://action/card/\#(m.id)">\#(card)</a>"#
                        : #"<span class="off" title="\#(String(localized: .claudeAnswerCardOff))">\#(card)</span>"#
                    // 반환 타입을 적어 둔다. 추론에 맡기면 리터럴이 GRDB의 `SQL`이 되고(FolioIndex를 거쳐 그 확장이
                    // 들어온다), 그 `joined()`가 대화에 `SQL(elements: ...)`를 찍는다.
                    let offered = Self.offered(m, superseded: superseded, describe: describe).count
                    let proposals = (m.proposals ?? []).enumerated().map { i, p -> String in
                        var line = describe(p)
                        let replaced = p.applied != true && superseded.contains(ProposalRef(message: m.id, index: i))
                        if p.applied != true, !replaced, let waiting = Self.waiting(m, i, superseded: superseded, describe: describe) {
                            line.refusal = Self.reason(waiting)
                        }
                        let button =
                            p.applied == true
                            ? #"<span class="done">\#(String(localized: .claudeProposalApplied))</span>"#
                            : replaced
                                ? #"<span class="off">\#(String(localized: .claudeProposalSuperseded))</span>"#
                                : line.refusal.map { _ in #"<span class="off">\#(String(localized: .claudeProposalUnavailable))</span>"# }
                                    ?? #"<a href="folio://action/apply/\#(m.id)/\#(i)">\#(String(localized: .claudeProposalApply))</a>"#
                        let why = p.applied == true || replaced ? nil : line.refusal ?? p.failure
                        let reason = why.map { #"<span class="why">\#(escape($0))</span>"# } ?? ""
                        let change = replaced ? "" : line.change.map(changeHTML) ?? ""
                        return
                            #"<div class="proposal"><div class="row"><span>\#(escape(line.text))\#(reason)</span>\#(button)</div>\#(change)</div>"#
                    }.joined()

                    let applyAll =
                        offered < 2
                        ? ""
                        : #"<div class="apply-all"><a href="folio://action/applyall/\#(m.id)">\#(String(localized: .claudeProposalApplyAll(offered)))</a></div>"#
                    return #"""
                        <div class="msg assistant">\#(body)\#(proposals)\#(applyAll)<div class="actions">\#
                        <a href="folio://action/copy/\#(m.id)">\#(String(localized: .claudeAnswerCopy))</a>\#
                        <a href="folio://action/insert/\#(m.id)">\#(String(localized: .claudeAnswerInsert))</a>\#
                        <a href="folio://action/newnote/\#(m.id)">\#(String(localized: .claudeAnswerNewNote))</a>\#
                        \#(cardLink)</div></div>
                        """#
                }
            }
        return "<style>\(css)</style><div class=\"chat edge-fade\">\(messages.joined())</div>"
    }

    static let css = """
        :root { font-size: 14px; } html, body.note { height: 100%; margin: 0; padding: 0; max-width: none; overflow: hidden; --body: 14px; }
        .chat { box-sizing: border-box; height: 100vh; overflow-y: auto; display: flex; flex-direction: column-reverse; gap: 14px; padding: 14px 16px; }
        .msg > :first-child { margin-top: 0; } .msg > :last-child { margin-bottom: 0; } .msg h1 { font-size: 19px; } .msg h2 { font-size: 16px; margin-top: 18px; }
        .user { align-self: flex-end; max-width: 85%; padding: 8px 12px; border-radius: 14px; background: var(--fill); }
        .actions { display: flex; gap: 14px; margin-top: 8px; font-size: 12px; } .actions .off { color: var(--text-3); cursor: default; }
        .proposal { margin-top: 8px; padding: 8px 12px; border-radius: 12px; background: var(--fill); font-size: 13px; }
        .proposal .row { display: flex; align-items: baseline; gap: 12px; }
        .proposal .row > span:first-child { flex: 1; } .proposal .off, .proposal .done { color: var(--text-3); cursor: default; }
        .proposal .why { display: block; margin-top: 4px; font-size: 12px; color: var(--text-3); }
        .change { margin-top: 8px; } .change summary { font-size: 12px; color: var(--text-2); cursor: default; }
        .diff { margin-top: 8px; padding: 4px 0; border-radius: 8px; background: var(--code-fill); overflow-x: auto;
          font: 12px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
        .diff .l { white-space: pre-wrap; padding: 0 8px 0 24px; text-indent: -16px; min-height: 18px; }
        .diff .add { background: color-mix(in srgb, var(--c-example) 16%, transparent); }
        .diff .del { background: color-mix(in srgb, var(--c-danger) 14%, transparent); }
        .diff .skip, .diff .label { color: var(--text-3); font-family: -apple-system, sans-serif; }
        .diff .gap { height: 8px; }
        .apply-all { margin-top: 8px; font-size: 13px; text-align: right; }
        .figure { margin-top: 8px; padding: 8px; border-radius: 8px; background: var(--card); box-shadow: inset 0 0 0 1px var(--line-soft); }
        .figure img { display: block; max-width: 100%; max-height: 240px; margin: 0 auto; }
        """

    static func changeHTML(_ change: ProposalLine.Change) -> String {
        func row(_ kind: String, _ sign: String, _ text: String) -> String { #"<div class="l \#(kind)">\#(sign) \#(escape(text))</div>"# }
        var rows: [String] = []
        var added = 0, removed = 0

        switch change {
        case .figure(let svg):
            return figureHTML(svg)
        case .rewrite(let lines):
            guard !lines.isEmpty else {
                return #"<div class="why">\#(String(localized: .claudeProposalNoChanges))</div>"#
            }
            for line in lines {
                switch line {
                case .same(let s): rows.append(row("same", " ", s))
                case .removed(let s): rows.append(row("del", "-", s)); removed += 1
                case .added(let s): rows.append(row("add", "+", s)); added += 1
                case .skipped(let n): rows.append(#"<div class="l skip">\#(String(localized: .claudeProposalSkipped(n)))</div>"#)
                }
            }
        case .edit(let replacements, let append):
            for (i, r) in replacements.enumerated() {
                if i > 0 { rows.append(#"<div class="gap"></div>"#) }
                let old = TextDiff.split(r.old), new = TextDiff.split(r.new)
                rows += old.map { row("del", "-", $0) } + new.map { row("add", "+", $0) }
                removed += old.count
                added += new.count
            }
            if let append {
                if !replacements.isEmpty { rows.append(#"<div class="gap"></div>"#) }
                let lines = TextDiff.split(append)
                rows.append(#"<div class="l label">\#(String(localized: .claudeProposalAppended))</div>"#)
                rows += lines.map { row("add", "+", $0) }
                added += lines.count
            }
        }

        return
            #"<details class="change"><summary>\#(String(localized: .claudeProposalChanges(added, removed)))</summary><div class="diff">\#(rows.joined())</div></details>"#
    }

    // `<img>` 안의 SVG는 페이지의 모양을 따르므로 패널이 다크일 때 다크 규칙이 보인다. 그 안에서는 스크립트를 돌리지
    // 않고 아무것도 불러오지 않는다.
    static func figureHTML(_ svg: String) -> String {
        let data = Data(svg.utf8).base64EncodedString()
        return
            #"<details class="change" open><summary>\#(String(localized: .claudeProposalFigure))</summary><div class="figure"><img src="data:image/svg+xml;base64,\#(data)" alt=""></div></details>"#
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
