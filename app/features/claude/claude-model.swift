import FolioActions
import FolioAI
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
    /// The tab's panes, which the window's one panel serves (`ContextBuilder.panes`).
    var panes: ContextItem?
    var added: [ContextItem] = []
    var removed: Set<String> = []
    var sending = false
    var status: String?
    var failed: String?
    /// The answer's current message only: an answer that reads with tools comes as several, and the ones before the
    /// last lead up to tool calls rather than answer.
    var partial: String?
    /// The tool the answer called last, until it writes again.
    var tool: String?
    /// Its input so far, which says what `action_run` runs.
    var toolInput = ""
    var stopped = false
    /// The chat that answer belongs to: switching chats mid-answer must not show it under another conversation.
    var answering: UUID?
    var openNote: UUID?
    private var answer: Task<Void, Never>?
    /// Tests answer through a fake provider; the app asks the workspace.
    private let client: ((LoadedCourse) -> ClaudeClient)?
    var cardDraft: CardDraft?
    /// A proposed change that removes or moves, waiting on the panel's confirmation.
    var confirming: PendingProposal?

    struct PendingProposal: Identifiable {
        var message: UUID
        /// Nil for all of the answer's proposals at once.
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
        let items = ContextBuilder.chatItems(course: course.file, rules: workspace.settings.noteRules, panes: panes, openNote: openNoteItem,
                                             alsoOpen: alsoOpenItems, added: added, removed: removed, now: .now)
        return ContextBuilder.build(items, budgetTokens: ContextBuilder.chatBudgetTokens)
    }

    func tokens(_ built: BuiltContext) -> String {
        String(localized: .claudeContextTokens(built.included.map(ContextBuilder.estimate).reduce(0, +).formatted()))
    }

    var chatOptions: [PickOption<UUID?>] {
        [PickOption(id: UUID?.none, title: String(localized: .claudeNewChat))] + chats.map { PickOption(id: Optional($0.model.id), title: $0.model.title) }
    }

    /// A message or a retry left from one chat doesn't belong under the next.
    func select(_ id: UUID?) {
        chatID = id
        status = nil
        failed = nil
        stopped = false
    }

    /// Readable files grouped by role in the materials page's order, unclassified last, so a file is found where that
    /// page shows it.
    func materials(_ course: LoadedCourse) -> [Material] {
        let readable = course.file.materials.filter { !$0.isFolder && [.classified, .unclassified].contains($0.status) && CourseStore.canReadContext($0.path) }
        return MaterialRole.allCases.flatMap { role in readable.filter { $0.status == .classified && $0.role == role } }
            + readable.filter { $0.status != .classified || $0.role == nil }
    }

    func addOptions(_ course: LoadedCourse) -> [PickOption<UUID>] {
        notes.compactMap { n in n.meta.id.map { PickOption(id: $0, title: n.title, section: String(localized: .claudeAddNotes)) } }
            + materials(course).map { m in
                PickOption(id: m.id, title: (m.path as NSString).lastPathComponent, detail: m.path,
                           section: m.status == .classified ? m.role?.label ?? String(localized: .claudeAddMaterials) : String(localized: .claudeAddUnclassified))
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

    /// The note an answer's `[[제목]]` names, found in the course as a note's own title link is.
    func noteId(titled title: String, course: LoadedCourse) -> UUID? {
        ((try? course.store.notes()) ?? []).linked(title)?.meta.id
    }

    func noteContext(_ id: UUID, course: LoadedCourse, open: Bool) -> ContextItem? {
        guard let note = try? course.store.note(id: id), let text = try? course.store.read(note) else { return nil }
        let body = Frontmatter.split(text).body
        let images = course.store.contextImages(of: note, body: body).map { ContextItem.Image(name: $0.name, data: $0.data) }
        return ContextBuilder.note(id: id, title: note.title, path: course.store.notePath(of: note.url), body: body, images: images, open: open)
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
        if let m = materials(course).first(where: { $0.id == id }) { add(materialContext(m, course: course)) } else { add(noteContext(id, course: course, open: false)) }
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
        // Read again from disk: the note was read when it opened, and has likely been edited since.
        loadOpenNote(openNote, course: course)
        let context = built(course)
        var doc = chats.first { $0.model.id == chatID } ?? StoredDocument(new: Chat(device: workspace.device, at: .now, title: String(question.prefix(40))))
        doc.model.messages.append(ChatMessage(role: .user, text: question, at: .now, context: context.included.map(\.title)))

        // The question is kept in memory only until the answer arrives, so a failed request leaves no half-written chat.
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
            // Shown every half second rather than per piece: each update reloads the conversation's page.
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
                // The API provider reports a cancelled request as a URL error, not a CancellationError.
                stopped = Task.isCancelled
                status = stopped ? String(localized: .claudeStatusStopped) : Self.message(for: error)
            }

            if doc.model.messages.isEmpty {
                chats.removeAll { $0.model.id == doc.model.id }
                // Otherwise the picker points at a chat that no longer exists and shows a blank label.
                if chatID == doc.model.id { chatID = nil }
            } else {
                replace(doc)
            }
            answering = nil
            sending = false
            answer = nil
        }
    }

    /// Ends the request, and with it the `claude` process. The question goes back to the resend button, and the chat
    /// keeps no half of it.
    func stop() { answer?.cancel() }

    func replace(_ doc: StoredDocument<Chat>) {
        chats.removeAll { $0.model.id == doc.model.id }
        chats.insert(doc, at: 0)
    }

    /// `folio://action/<copy|insert|newnote|card|applyall>/<message ID>` and `folio://action/apply/<message ID>/<proposal>` from
    /// the answer's links. `openNote` is the note open beside the panel, which `insert` writes into through
    /// `insertIntoNote`; without one it makes a free note. `openUnit` is the unit the units page shows, where a card goes.
    func handle(_ url: URL, course: LoadedCourse, openNote: UUID?, openUnit: UUID? = nil, insertIntoNote: (String) -> Void, showNote: (UUID) -> Void) {
        let parts = url.pathComponents
        guard parts.count >= 3, let id = UUID(uuidString: parts[2]),
              let message = chat?.messages.first(where: { $0.id == id }) else { return }

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
            if let note = createNote(title: Self.noteTitle(message.text) ?? chat?.title ?? Self.answerTitle, body: message.text, course: course) {
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
                  let i = messages.firstIndex(where: { $0.id == id }) else { break }
            // The question it answered is the card's prompt; the answer its model answer. Both stay editable in the sheet.
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

    /// The chat as the panel shows it, with the answer being written on top.
    func page(_ chat: Chat, cards: Bool) -> String {
        Self.html(chat, partial: sending && answering == chatID ? partial : nil, cards: cards, superseded: superseded(chat), describe: describe)
    }

    func superseded(_ chat: Chat) -> Set<ProposalRef> { chat.supersededProposals(targets: Actions.targets) }

    /// The proposal's line in the answer: what it would do, why it can't when the folder no longer allows it, and
    /// what it changes in a note. Each is a dry run, and the page is drawn again twice a second while an answer is
    /// written, so lines are kept until the folder changes.
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
            line = ProposalLine(text: workspace.summary(action), refusal: pending ? workspace.refusal(action) : nil,
                                change: pending ? change(proposal) : nil)
        } else {
            line = ProposalLine(text: proposal.command, refusal: String(localized: .claudeProposalUnknown))
        }
        lines[proposal] = line
        return line
    }

    @ObservationIgnored private var lines: [ActionProposal: ProposalLine] = [:]
    @ObservationIgnored private var linesRevision = -1
    /// How many lines were worked out rather than reused; tests read it.
    @ObservationIgnored private(set) var described = 0

    /// Read from the proposal's input: the action's fields are internal to FolioActions.
    func change(_ proposal: ActionProposal) -> ProposalLine.Change? {
        func string(_ key: String) -> String? { if case .string(let s)? = proposal.input[key] { s } else { nil } }
        switch proposal.command {
        case NoteWrite.command:
            guard let text = string("text"), let course = string("course").flatMap(UUID.init(uuidString:)).flatMap(workspace.course),
                  let path = string("note"), let note = course.store.note(at: path, in: course.file),
                  let old = try? course.store.read(note) else { return nil }
            return .rewrite(TextDiff.lines(from: old, to: text))
        case NoteEdit.command:
            let replacements = proposal.input["replacements"].flatMap { try? JSONDecoder().decode([NoteEdit.Replacement].self, from: JSONEncoder().encode($0)) } ?? []
            return .edit(replacements, append: string("append").flatMap { $0.isEmpty ? nil : $0 })
        case NoteFigureAdd.command, NoteFigureWrite.command:
            return string("svg").map(ProposalLine.Change.figure)
        default:
            return nil
        }
    }

    /// The proposals "apply all" runs: those still offered, in the answer's order. The page counts the same ones. One
    /// made on top of earlier proposals goes along when all of those do, since they are checked and run in order.
    static func offered(_ message: ChatMessage, superseded: Set<ProposalRef>, describe: (ActionProposal) -> ProposalLine) -> [Int] {
        var offered: [Int] = []
        for (i, p) in (message.proposals ?? []).enumerated() where p.applied != true && !superseded.contains(ProposalRef(message: message.id, index: i)) {
            switch waiting(message, i, superseded: superseded, describe: describe) {
            case nil: if describe(p).refusal == nil { offered.append(i) }
            case .earlier(let before)?: if before.allSatisfy(offered.contains) { offered.append(i) }
            case .blocked?: break
            }
        }
        return offered
    }

    /// Whether the proposal at `index` waits on earlier proposals of its answer that aren't applied (`after`).
    static func waiting(_ message: ChatMessage, _ index: Int, superseded: Set<ProposalRef>,
                        describe: (ActionProposal) -> ProposalLine) -> ChatMessage.Waiting? {
        let proposals = message.proposals ?? []
        return message.waiting(index) { j in
            superseded.contains(ProposalRef(message: message.id, index: j)) || describe(proposals[j]).refusal != nil
        }
    }

    /// The line's reason for one that waits; `1, 2` names the earlier proposals as the panel numbers them.
    static func reason(_ waiting: ChatMessage.Waiting) -> String {
        switch waiting {
        case .earlier(let before): String(localized: .claudeProposalWaiting(before.map { String($0 + 1) }.joined(separator: ", ")))
        case .blocked(let before): String(localized: .claudeProposalWaitingBlocked(before.map { String($0 + 1) }.joined(separator: ", ")))
        }
    }

    func confirm(_ pending: PendingProposal, course: LoadedCourse) {
        if let index = pending.index { apply(message: pending.message, index: index, course: course, confirmed: true) }
        else { applyAll(message: pending.message, course: course, confirmed: true) }
    }

    /// Runs the proposal through the workspace like any button would, after the same confirmation a removal asks for.
    func apply(message: UUID, index: Int, course: LoadedCourse, confirmed: Bool) {
        guard var doc = chats.first(where: { $0.model.id == chatID }),
              let m = doc.model.messages.firstIndex(where: { $0.id == message }),
              let proposals = doc.model.messages[m].proposals, proposals.indices.contains(index),
              case let proposal = proposals[index], proposal.applied != true,
              let action = workspace.action(proposal) else { return }

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

    /// Every proposal of the answer still offered, after one question for all that ask. All are checked in order
    /// before any is written, so one refused leaves the folder as it was; one that fails while running stops the
    /// rest, as applying them one by one would.
    func applyAll(message: UUID, course: LoadedCourse, confirmed: Bool) {
        guard var doc = chats.first(where: { $0.model.id == chatID }),
              let m = doc.model.messages.firstIndex(where: { $0.id == message }) else { return }
        let picked = Self.offered(doc.model.messages[m], superseded: superseded(doc.model), describe: describe).compactMap { i in
            doc.model.messages[m].proposals.flatMap { workspace.action($0[i]) }.map { (index: i, action: $0) }
        }
        guard !picked.isEmpty else { return }

        // A plain dry run carries course.json from one to the next but writes no file, so a proposal made on top of a
        // note the answer makes first is checked again in a staged copy, where the note is there.
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

    /// Records the outcome on the proposal; true when it went through.
    private func run(_ action: any Action, at index: Int, of message: Int, in doc: inout StoredDocument<Chat>) -> Bool {
        do {
            _ = try workspace.runThrowing(action)
            doc.model.messages[message].proposals?[index].applied = true
            doc.model.messages[message].proposals?[index].failure = nil
            return true
        } catch {
            // Saved with the chat, so the panel keeps showing why and the next question tells Claude.
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

    /// A free note holding `text`, for an answer saved while no note is open.
    func createNote(title: String, body: String, course: LoadedCourse) -> UUID? {
        workspace.run(NoteAdd(course: course.id, title: title, body: body))?.made
    }

    // MARK: Helpers

    /// `mcp__folio__note_show` reads as `note show`. A write only makes a proposal in the panel's server, which the line
    /// says, so the user doesn't wait for a change that won't happen until they apply it.
    static func toolLabel(_ name: String, input: String = "") -> String {
        let prefix = "mcp__folio__"
        var tool = name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
        // The server's two tools for actions the panel doesn't list (`MCPServer.generalTools` in folio-cli).
        if tool == "action_search" { return String(localized: .claudeToolSearching) }
        if tool == "action_run" {
            // The input streams in after the name, so the command shows once its `action` has arrived whole.
            guard let match = input.firstMatch(of: /"action"\s*:\s*"([^"\\]+)"/) else { return String(localized: .claudeToolChoosing) }
            tool = String(match.1).replacing(/^folio\s+/, with: "")
        }
        // The MCP server's naming (`MCPServer.name` in folio-cli, which the app doesn't link).
        let named = tool.replacing(" --", with: "_").replacing(" ", with: "_")
        if let write = Actions.all.first(where: { $0.command.replacing(" --", with: "_").replacing(" ", with: "_") == named }) {
            return String(localized: .claudeToolProposing(write.command))
        }
        return String(localized: .claudeToolReading(tool.replacing("_", with: " ")))
    }

    /// Kept out of the string catalog: it is written into the note file as its title.
    static let answerTitle = "Claude 답변"

    /// The answer's first `# heading`, which names the note better than the question it answered.
    static func noteTitle(_ markdown: String) -> String? {
        markdown.split(separator: "\n").first { $0.hasPrefix("# ") }.map { $0.dropFirst(2).trimmingCharacters(in: .whitespaces) }
    }

    nonisolated static func message(for error: any Error) -> String {
        switch error as? ClaudeError {
        case .missingAPIKey: String(localized: .claudeErrorMissingKey)
        case .http(let status, let body):
            status == 401 ? String(localized: .claudeErrorAuth)
                // The CLI reports its own errors with no HTTP status; its message says more than a code would.
                : status == 0 ? String(localized: .claudeErrorFailedBody(String(body.prefix(200)))) : String(localized: .claudeErrorHttp(status))
        case .refused: String(localized: .claudeErrorRefused)
        case .truncated: String(localized: .claudeErrorTruncated)
        case .invalidOutput, nil: String(localized: .claudeErrorFailedBody(error.localizedDescription))
        }
    }

    /// The whole conversation as one page. `column-reverse` keeps the newest message in view without JavaScript.
    static func html(_ chat: Chat, partial: String? = nil, cards: Bool = true, superseded: Set<ProposalRef> = [],
                     describe: (ActionProposal) -> ProposalLine = { ProposalLine(text: $0.command) }) -> String {
        let writing = partial.map { #"<div class="msg assistant">\#(HTMLRenderer.render(answer: $0))</div>"# }
        let card = String(localized: .claudeAnswerCard)
        let messages = (writing.map { [$0] } ?? []) + chat.messages.reversed().map { m in
            let body = HTMLRenderer.render(answer: m.text)
            switch m.role {
            case .user:
                return #"<div class="msg user">\#(body)</div>"#
            case .assistant:
                let cardLink = cards ? #"<a href="folio://action/card/\#(m.id)">\#(card)</a>"#
                    : #"<span class="off" title="\#(String(localized: .claudeAnswerCardOff))">\#(card)</span>"#
                // The return type is spelled out: left to inference, the literals become GRDB's `SQL` (its extensions
                // leak in through FolioIndex), whose `joined()` then prints `SQL(elements: …)` into the chat.
                let offered = Self.offered(m, superseded: superseded, describe: describe).count
                let proposals = (m.proposals ?? []).enumerated().map { i, p -> String in
                    var line = describe(p)
                    let replaced = p.applied != true && superseded.contains(ProposalRef(message: m.id, index: i))
                    // Its own dry run fails against the folder until the ones it builds on are applied; that, not the
                    // missing item, is the reason to show.
                    if p.applied != true, !replaced, let waiting = Self.waiting(m, i, superseded: superseded, describe: describe) {
                        line.refusal = Self.reason(waiting)
                    }
                    let button = p.applied == true ? #"<span class="done">\#(String(localized: .claudeProposalApplied))</span>"#
                        : replaced ? #"<span class="off">\#(String(localized: .claudeProposalSuperseded))</span>"#
                        : line.refusal.map { _ in #"<span class="off">\#(String(localized: .claudeProposalUnavailable))</span>"# }
                        ?? #"<a href="folio://action/apply/\#(m.id)/\#(i)">\#(String(localized: .claudeProposalApply))</a>"#
                    // In the line, not a tooltip: a reason only shown on hover reads as a silent failure.
                    let why = p.applied == true || replaced ? nil : line.refusal ?? p.failure
                    let reason = why.map { #"<span class="why">\#(escape($0))</span>"# } ?? ""
                    let change = replaced ? "" : line.change.map(changeHTML) ?? ""
                    return #"<div class="proposal"><div class="row"><span>\#(escape(line.text))\#(reason)</span>\#(button)</div>\#(change)</div>"#
                }.joined()

                // Only with two or more: for one, its own link is the same button.
                let applyAll = offered < 2 ? ""
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

    /// What a note proposal changes, folded shut so the answer stays readable; opened, the user approves what they
    /// read rather than a one-line summary.
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

        return #"<details class="change"><summary>\#(String(localized: .claudeProposalChanges(added, removed)))</summary><div class="diff">\#(rows.joined())</div></details>"#
    }

    /// The picture as the note would show it, on the note's card. An SVG in an `<img>` follows the page's appearance,
    /// so its dark rule shows when the panel is dark; it runs no script and loads nothing there.
    static func figureHTML(_ svg: String) -> String {
        let data = Data(svg.utf8).base64EncodedString()
        return #"<details class="change" open><summary>\#(String(localized: .claudeProposalFigure))</summary><div class="figure"><img src="data:image/svg+xml;base64,\#(data)" alt=""></div></details>"#
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

struct ProposalLine: Equatable {
    var text: String
    /// Why it can't be applied now; nil when it can, or once it is applied.
    var refusal: String?
    /// What it does to a note, while it is not applied.
    var change: Change?

    enum Change: Equatable {
        /// The whole note written again, against the note on disk.
        case rewrite([TextDiff.Line])
        case edit([NoteEdit.Replacement], append: String?)
        /// A note figure written new or again: the SVG it would be.
        case figure(String)
    }
}

/// Collects an answer's pieces off the main actor; the panel reads the state so far on its own schedule.
final class AnswerStream: Sendable {
    struct State: Sendable, Equatable {
        var text: String?
        var tool: String?
        var toolInput = ""
    }

    private let state = Mutex(State())

    var now: State { state.withLock { $0 } }

    func take(_ event: StreamEvent) {
        state.withLock { s in
            switch event {
            // A new message starts over: the text before it led up to a tool call, and only the last message is kept.
            case .turn: s.text = nil
            case .text(let piece): s.text = (s.text ?? "") + piece; s.tool = nil
            case .tool(let name): s.tool = name; s.toolInput = ""
            case .toolInput(let piece): s.toolInput += piece
            }
        }
    }
}
