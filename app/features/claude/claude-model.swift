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
    var added: [ContextItem] = []
    var removed: Set<String> = []
    var sending = false
    var status: String?
    var failed: String?
    var partial: String?
    /// The chat that answer belongs to: switching chats mid-answer must not show it under another conversation.
    var answering: UUID?
    var cardDraft: CardDraft?
    /// A proposed change that removes or moves, waiting on the panel's confirmation.
    var confirming: PendingProposal?

    struct PendingProposal: Identifiable {
        var message: UUID
        var index: Int
        var question: String
        var id: String { "\(message)/\(index)" }
    }

    init(workspace: Workspace) { self.workspace = workspace }

    var hasKey: Bool { workspace.claudeReady }

    var chat: Chat? { chats.first { $0.model.id == chatID }?.model }

    func built(_ course: LoadedCourse) -> BuiltContext {
        let items = ContextBuilder.chatItems(course: course.file, rules: workspace.settings.noteRules, openNote: openNoteItem,
                                             added: added, removed: removed, now: .now)
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

    func loadOpenNote(_ id: UUID?, course: LoadedCourse) {
        openNoteItem = id.flatMap { noteContext($0, course: course, open: true) }
    }

    static func notes(_ course: LoadedCourse) -> [NoteFile] {
        ((try? course.store.notes()) ?? []).filter { $0.meta.id != nil }
    }

    func noteContext(_ id: UUID, course: LoadedCourse, open: Bool) -> ContextItem? {
        guard let note = try? course.store.note(id: id), let text = try? course.store.read(note) else { return nil }
        let body = Frontmatter.split(text).body
        let images = course.store.contextImages(of: note, body: body).map { ContextItem.Image(name: $0.name, data: $0.data) }
        return ContextBuilder.note(id: id, title: note.title, body: body, images: images, open: open)
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
        partial = nil
        let client = workspace.claude(for: course, folioTools: true)
        let asked = doc.model
        let stream = AnswerStream()
        Task {
            var doc = doc
            // Shown every half second rather than per piece: each update reloads the conversation's page.
            let ticker = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    if let text = stream.text { partial = text }
                }
            }
            defer { ticker.cancel(); partial = nil }
            do {
                let reply = try await client.reply(to: asked, context: context) { stream.append($0) }
                doc.model.messages.append(ChatMessage(role: .assistant, text: reply.text, at: .now, proposals: reply.proposals))
                doc.model.touch(by: workspace.device, at: .now)
                let saved = doc
                // folio:not-an-action chat history is not an action
                workspace.perform { try course.store.save(saved) }
            } catch {
                doc.model.messages.removeLast()
                failed = question
                status = Self.message(for: error)
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
        }
    }

    func replace(_ doc: StoredDocument<Chat>) {
        chats.removeAll { $0.model.id == doc.model.id }
        chats.insert(doc, at: 0)
    }

    /// `folio://action/<copy|insert|newnote|card>/<message ID>` and `folio://action/apply/<message ID>/<proposal>` from
    /// the answer's links. `openNote` is the note open beside the panel, which `insert` writes into through
    /// `insertIntoNote`; without one it makes a free note.
    func handle(_ url: URL, course: LoadedCourse, openNote: UUID?, insertIntoNote: (String) -> Void, showNote: (UUID) -> Void) {
        let parts = url.pathComponents
        guard parts.count >= 3, let id = UUID(uuidString: parts[2]),
              let message = chat?.messages.first(where: { $0.id == id }) else { return }
        switch parts[1] {
        case "apply":
            guard parts.count == 4, let index = Int(parts[3]) else { break }
            apply(message: id, index: index, course: course, confirmed: false)
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
            guard let unit = course.file.units.first, let messages = chat?.messages,
                  let i = messages.firstIndex(where: { $0.id == id }) else { break }
            // The question it answered is the card's prompt; the answer its model answer. Both stay editable in the sheet.
            var draft = CardDraft(unitId: unit.id)
            draft.prompt = messages[..<i].last { $0.role == .user }?.text ?? ""
            draft.answer = message.text
            cardDraft = draft
        default:
            break
        }
        failed = nil
    }

    // MARK: Proposals

    /// The proposal's line in the answer: what it would do, and why it can't when the folder no longer allows it.
    func describe(_ proposal: ActionProposal) -> (text: String, refusal: String?) {
        guard let action = workspace.action(proposal) else { return (proposal.command, String(localized: .claudeProposalUnknown)) }
        return (workspace.summary(action), proposal.applied == true ? nil : workspace.refusal(action))
    }

    /// Runs the proposal through the workspace like any button would, after the same confirmation a removal asks for.
    func apply(message: UUID, index: Int, course: LoadedCourse, confirmed: Bool) {
        guard var doc = chats.first(where: { $0.model.id == chatID }),
              let m = doc.model.messages.firstIndex(where: { $0.id == message }),
              let proposals = doc.model.messages[m].proposals, proposals.indices.contains(index),
              case let proposal = proposals[index], proposal.applied != true,
              let action = workspace.action(proposal) else { return }
        if !confirmed, let question = workspace.confirmation(action) {
            confirming = PendingProposal(message: message, index: index, question: question)
            return
        }
        guard workspace.run(action) != nil else { return }
        doc.model.messages[m].proposals?[index].applied = true
        doc.model.touch(by: workspace.device, at: .now)
        let saved = doc
        // folio:not-an-action chat history is not an action
        workspace.perform { try course.store.save(saved) }
        replace(doc)
        status = String(localized: .claudeStatusApplied(workspace.summary(action)))
    }

    /// A free note holding `text`, for an answer saved while no note is open.
    func createNote(title: String, body: String, course: LoadedCourse) -> UUID? {
        workspace.run(NoteAdd(course: course.id, title: title, body: body))?.made
    }

    // MARK: Helpers

    /// Kept out of the string catalog: it is written into the note file as its title.
    static let answerTitle = "Claude 답변"

    /// The answer's first `# heading`, which names the note better than the question it answered.
    static func noteTitle(_ markdown: String) -> String? {
        markdown.split(separator: "\n").first { $0.hasPrefix("# ") }.map { $0.dropFirst(2).trimmingCharacters(in: .whitespaces) }
    }

    static func message(for error: any Error) -> String {
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
    static func html(_ chat: Chat, partial: String? = nil, cards: Bool = true,
                     describe: (ActionProposal) -> (text: String, refusal: String?) = { ($0.command, nil) }) -> String {
        let writing = partial.map { #"<div class="msg assistant">\#(HTMLRenderer.render(markdown: $0))</div>"# }
        let card = String(localized: .claudeAnswerCard)
        let messages = (writing.map { [$0] } ?? []) + chat.messages.reversed().map { m in
            let body = HTMLRenderer.render(markdown: m.text)
            switch m.role {
            case .user:
                return #"<div class="msg user">\#(body)</div>"#
            case .assistant:
                let cardLink = cards ? #"<a href="folio://action/card/\#(m.id)">\#(card)</a>"#
                    : #"<span class="off" title="\#(String(localized: .claudeAnswerCardOff))">\#(card)</span>"#
                let proposals = (m.proposals ?? []).enumerated().map { i, p in
                    let (text, refusal) = describe(p)
                    let button = p.applied == true ? #"<span class="done">\#(String(localized: .claudeProposalApplied))</span>"#
                        : refusal.map { #"<span class="off" title="\#(escape($0))">\#(String(localized: .claudeProposalUnavailable))</span>"# }
                        ?? #"<a href="folio://action/apply/\#(m.id)/\#(i)">\#(String(localized: .claudeProposalApply))</a>"#
                    return #"<div class="proposal"><span>\#(escape(text))</span>\#(button)</div>"#
                }.joined()
                return #"""
                <div class="msg assistant">\#(body)\#(proposals)<div class="actions">\#
                <a href="folio://action/copy/\#(m.id)">\#(String(localized: .claudeAnswerCopy))</a>\#
                <a href="folio://action/insert/\#(m.id)">\#(String(localized: .claudeAnswerInsert))</a>\#
                <a href="folio://action/newnote/\#(m.id)">\#(String(localized: .claudeAnswerNewNote))</a>\#
                \#(cardLink)</div></div>
                """#
            }
        }
        return "<style>\(css)</style><div class=\"chat\">\(messages.joined())</div>"
    }

    static let css = """
    :root { font-size: 14px; } html, body.note { height: 100%; margin: 0; padding: 0; max-width: none; overflow: hidden; --body: 14px; }
    .chat { box-sizing: border-box; height: 100vh; overflow-y: auto; display: flex; flex-direction: column-reverse; gap: 14px; padding: 14px 16px; }
    .msg > :first-child { margin-top: 0; } .msg > :last-child { margin-bottom: 0; } .msg h1 { font-size: 19px; } .msg h2 { font-size: 16px; margin-top: 18px; }
    .user { align-self: flex-end; max-width: 85%; padding: 8px 12px; border-radius: 14px; background: var(--fill); }
    .actions { display: flex; gap: 14px; margin-top: 8px; font-size: 12px; } .actions .off { color: var(--text-3); cursor: default; }
    .proposal { display: flex; align-items: baseline; gap: 12px; margin-top: 8px; padding: 8px 12px; border-radius: 12px; background: var(--fill); font-size: 13px; }
    .proposal > span:first-child { flex: 1; } .proposal .off, .proposal .done { color: var(--text-3); cursor: default; }
    """

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// Collects an answer's pieces off the main actor; the panel reads the text so far on its own schedule.
final class AnswerStream: Sendable {
    private let buffer = Mutex<String?>(nil)

    var text: String? { buffer.withLock { $0 } }
    func append(_ piece: String) { buffer.withLock { $0 = ($0 ?? "") + piece } }
}
