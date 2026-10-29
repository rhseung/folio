import FolioAI
import FolioDomain
import FolioMarkdown
import FolioStorage
import SwiftUI
import Synchronization

/// The course's Claude panel: what will be sent, the conversation, and the question box.
/// Nothing leaves the device until the user presses send (docs/SPEC.md "데이터 전송 원칙").
struct ClaudePanel: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.accent) private var accent
    @Environment(\.showSettings) private var showSettings
    let course: LoadedCourse
    /// The note shown in the notes section; nil on other sections.
    let openNote: UUID?
    let insertIntoNote: (String) -> Void
    let showNote: (UUID) -> Void

    @State private var chats: [StoredDocument<Chat>] = []
    @State private var chatID: UUID?
    @State private var notes: [NoteFile] = []
    @State private var openNoteItem: ContextItem?
    @State private var added: [ContextItem] = []
    @State private var removed: Set<String> = []
    @State private var sending = false
    @State private var status: String?
    @State private var failed: String?
    /// The answer so far while it is being written.
    @State private var partial: String?
    /// The chat that answer belongs to: switching chats mid-answer must not show it under another conversation.
    @State private var answering: UUID?
    @State private var cardDraft: CardDraft?

    var hasKey: Bool { workspace.claudeReady }

    var chat: Chat? { chats.first { $0.model.id == chatID }?.model }

    var built: BuiltContext {
        let items = ContextBuilder.chatItems(course: course.file, rules: workspace.settings.noteRules, openNote: openNoteItem,
                                             added: added, removed: removed, now: .now)
        return ContextBuilder.build(items, budgetTokens: ContextBuilder.chatBudgetTokens)
    }

    var body: some View {
        let built = built
        VStack(spacing: 0) {
            header
            contextList(built)
                .padding(.horizontal, Theme.Space.m)
                .padding(.bottom, Theme.Space.m)
            Theme.Palette.lineSoft.frame(height: 1)
            conversation
            if sending || status != nil { statusLine }
            ChatComposer(enabled: hasKey, sending: sending, send: send)
        }
        .font(Theme.Typeface.body)
        .foregroundStyle(Theme.Palette.text)
        .task(id: course.id) {
            chats = workspace.chats(course)
            chatID = chats.first?.model.id
            notes = workspace.notes(course)
        }
        .task(id: openNote) { openNoteItem = openNote.flatMap { workspace.noteContext($0, course: course, open: true) } }
        .sheet(item: $cardDraft) { draft in
            CardEditorSheet(course: course, draft: draft, units: course.file.units) { status = "카드를 만들었습니다" }
        }
    }

    var header: some View {
        HStack(spacing: Theme.Space.s) {
            // A message or a retry left from one chat doesn't belong under the next.
            SearchSelect(selection: Binding(get: { chatID }, set: { chatID = $0; status = nil; failed = nil }),
                         options: [PickOption(id: UUID?.none, title: "새 대화")] + chats.map { PickOption(id: Optional($0.model.id), title: $0.model.title) })
            Spacer()
            Button { chatID = nil; status = nil; failed = nil } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.ghost)
                .help("새 대화")
        }
        .padding(Theme.Space.m)
    }

    func contextList(_ built: BuiltContext) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.s) {
                Caption("보낼 맥락")
                Spacer()
                Text("약 \(built.included.map(ContextBuilder.estimate).reduce(0, +).formatted()) 토큰")
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
                addMenu
            }
            .padding(.horizontal, Theme.Space.xs)
            .padding(.bottom, Theme.Space.xxs)
            ScrollView {
                VStack(spacing: Theme.Space.xs) {
                    ForEach(built.included + built.dropped) { item in
                        contextRow(item, dropped: built.dropped.contains(item))
                    }
                }
            }
            // About six rows; past that the list scrolls instead of squeezing the conversation below it.
            .frame(maxHeight: 200)
            .fixedSize(horizontal: false, vertical: true)
            if !removed.isEmpty {
                Button("뺀 항목 되돌리기") { removed = [] }
                    .buttonStyle(.ghost).font(Theme.Typeface.caption)
                    .padding(.horizontal, Theme.Space.xs)
            }
        }
    }

    func contextRow(_ item: ContextItem, dropped: Bool) -> some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: Self.symbol(item.tier)).foregroundStyle(Theme.Palette.textTertiary).frame(width: 16)
            Text(item.title).lineLimit(1).truncationMode(.middle).strikethrough(dropped)
            if !item.images.isEmpty {
                Label("\(item.images.count)", systemImage: "photo").labelStyle(.titleAndIcon)
                    .font(Theme.Typeface.caption).monospacedDigit().foregroundStyle(Theme.Palette.textTertiary)
                    .help("그림 \(item.images.count)장을 함께 보냅니다")
            }
            Spacer(minLength: Theme.Space.xs)
            Text(dropped ? "한도 초과로 뺌" : ContextBuilder.estimate(item).formatted())
                .font(Theme.Typeface.caption).monospacedDigit()
                .foregroundStyle(dropped ? Theme.Palette.warning : Theme.Palette.textTertiary)
            Button { removed.insert(item.id) } label: { Image(systemName: "xmark").font(Theme.Glyph.small.weight(.semibold)) }
                .buttonStyle(.ghost)
                .help("맥락에서 빼기")
        }
        .padding(Theme.Inset.listRow)
        .surface(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.control))
        .contextMenu { Button("맥락에서 빼기", role: .destructive) { removed.insert(item.id) } }
    }

    var addMenu: some View {
        let readable = course.file.materials.filter { !$0.isFolder && [.classified, .unclassified].contains($0.status) && CourseStore.canReadContext($0.path) }
        // Grouped by role in the materials page's order, unclassified last, so a file is found where that page shows it.
        let materials = MaterialRole.allCases.flatMap { role in readable.filter { $0.status == .classified && $0.role == role } }
            + readable.filter { $0.status != .classified || $0.role == nil }
        let options = notes.compactMap { n in n.meta.id.map { PickOption(id: $0, title: n.title, section: "노트") } }
            + materials.map { m in
                PickOption(id: m.id, title: (m.path as NSString).lastPathComponent, detail: m.path,
                           section: m.status == .classified ? m.role?.label ?? "자료" : "미분류")
            }
        return SearchPicker(options: options, pick: { id in
            if let m = materials.first(where: { $0.id == id }) { add(workspace.materialContext(m, course: course)) } else { add(workspace.noteContext(id, course: course, open: false)) }
        }, prompt: "노트나 자료 찾기") {
            Image(systemName: "plus").foregroundStyle(Theme.Palette.textSecondary)
        }
        .help("노트나 자료를 맥락에 더하기")
    }

    @ViewBuilder var conversation: some View {
        if let chat, !chat.messages.isEmpty {
            HTMLView(body: Self.html(chat, partial: sending && answering == chatID ? partial : nil, cards: !course.file.units.isEmpty), onAction: handle)
        } else {
            VStack(spacing: Theme.Space.s) {
                Image(systemName: hasKey ? "sparkle" : "key")
                    .font(Theme.Glyph.large.weight(.semibold))
                    .foregroundStyle(hasKey ? accent.ink : Theme.Palette.textTertiary)
                Text(hasKey ? "이 과목에 대해 물어보세요" : "Claude 연결이 필요합니다").font(Theme.Typeface.bodyStrong)
                Text(hasKey ? "위의 맥락과 함께 보냅니다. 보내기를 누르기 전에는 아무것도 전송하지 않습니다."
                            : "설정의 Claude 항목에서 Claude Code 구독이나 API 키를 연결하면 이 과목의 맥락으로 대화할 수 있습니다.")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                if !hasKey { Button("설정 열기") { showSettings(.claude) }.padding(.top, Theme.Space.xs) }
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    var statusLine: some View {
        HStack(spacing: Theme.Space.s) {
            if sending {
                ProgressView().controlSize(.small)
                Text(partial == nil ? "답을 기다리는 중…" : "답을 쓰는 중…")
            } else if let status {
                Text(status)
            }
            Spacer(minLength: 0)
            if let failed, !sending {
                Button("다시 보내기") { send(failed) }.buttonStyle(.ghost)
            }
        }
        .font(Theme.Typeface.caption)
        .foregroundStyle(failed == nil ? Theme.Palette.textSecondary : Theme.Palette.danger)
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.s)
    }

    // MARK: Actions

    func add(_ item: ContextItem?) {
        guard let item else { return }
        removed.remove(item.id)
        added.removeAll { $0.id == item.id }
        added.append(item)
    }

    func send(_ question: String) {
        guard hasKey, !sending else { return }
        let context = built
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
        let client = workspace.claude(for: course)
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
                doc.model.messages.append(ChatMessage(role: .assistant, text: reply.text, at: .now))
                doc.model.touch(by: workspace.device, at: .now)
                // folio:not-an-action chat history is not an action
                workspace.save(doc, course: course)
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

    /// `folio://action/<copy|insert>/<message ID>` from the answer's links.
    func handle(_ url: URL) {
        let parts = url.pathComponents
        guard parts.count == 3, let id = UUID(uuidString: parts[2]),
              let message = chat?.messages.first(where: { $0.id == id }) else { return }
        switch parts[1] {
        case "copy":
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message.text, forType: .string)
            #else
            UIPasteboard.general.string = message.text
            #endif
            status = "복사했습니다"
        case "newnote":
            if let note = workspace.createNote(title: Self.noteTitle(message.text) ?? chat?.title ?? "Claude 답변", body: message.text, course: course) {
                notes = workspace.notes(course)
                showNote(note)
                status = "새 노트로 만들었습니다"
            }
        case "insert":
            if openNote != nil {
                insertIntoNote(message.text)
                status = "열린 노트 끝에 넣었습니다. 저장하면 파일에 반영됩니다."
            } else if let note = workspace.createNote(title: chat?.title ?? "Claude 답변", body: message.text, course: course) {
                notes = workspace.notes(course)
                showNote(note)
                status = "자유 노트를 새로 만들어 넣었습니다"
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

    // MARK: Helpers

    /// The answer's first `# heading`, which names the note better than the question it answered.
    static func noteTitle(_ markdown: String) -> String? {
        markdown.split(separator: "\n").first { $0.hasPrefix("# ") }.map { $0.dropFirst(2).trimmingCharacters(in: .whitespaces) }
    }

    static func symbol(_ tier: ContextItem.Tier) -> String {
        switch tier {
        case .courseSummary: "book.closed"
        case .userRules: "list.bullet.rectangle"
        case .focus: "doc.text"
        case .related: "paperclip"
        case .search: "magnifyingglass"
        }
    }

    static func message(for error: any Error) -> String {
        switch error as? ClaudeError {
        case .missingAPIKey: "API 키가 없습니다. 설정에서 넣어 주세요."
        case .http(let status, let body):
            status == 401 ? "인증에 실패했습니다. API 키나 Claude Code 로그인을 확인하세요."
                // The CLI reports its own errors with no HTTP status; its message says more than a code would.
                : status == 0 ? "요청이 실패했습니다: \(body.prefix(200))" : "요청이 실패했습니다 (HTTP \(status))."
        case .refused: "Claude가 이 요청에는 답하지 않았습니다."
        case .truncated: "답이 길어 중간에 끊겼습니다. 질문을 나눠 보세요."
        case .invalidOutput, nil: "요청이 실패했습니다: \(error.localizedDescription)"
        }
    }

    /// The whole conversation as one page. `column-reverse` keeps the newest message in view without JavaScript.
    static func html(_ chat: Chat, partial: String? = nil, cards: Bool = true) -> String {
        let writing = partial.map { #"<div class="msg assistant">\#(HTMLRenderer.render(markdown: $0))</div>"# }
        let messages = (writing.map { [$0] } ?? []) + chat.messages.reversed().map { m in
            let body = HTMLRenderer.render(markdown: m.text)
            switch m.role {
            case .user:
                return #"<div class="msg user">\#(body)</div>"#
            case .assistant:
                let card = cards ? #"<a href="folio://action/card/\#(m.id)">카드로 만들기</a>"#
                    : #"<span class="off" title="카드는 단원에 속합니다. 단원을 먼저 만드세요">카드로 만들기</span>"#
                return #"""
                <div class="msg assistant">\#(body)<div class="actions">\#
                <a href="folio://action/copy/\#(m.id)">복사</a>\#
                <a href="folio://action/insert/\#(m.id)">노트에 넣기</a>\#
                <a href="folio://action/newnote/\#(m.id)">새 노트로</a>\#
                \#(card)</div></div>
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
    """
}

/// The question box, floating on glass. Keeps its own text so typing doesn't re-render the conversation.
struct ChatComposer: View {
    let enabled: Bool
    let sending: Bool
    let send: (String) -> Void
    @State private var text = ""

    var question: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        // Last baseline, so longer text grows upward with the button kept by its last line. The button's center sits
        // 4.5pt above that baseline, the middle of a 13pt Hangul line; on its own image bottom the text hung 2-3pt low.
        HStack(alignment: .lastTextBaseline, spacing: Theme.Space.s) {
            TextField(enabled ? "질문하기" : "Claude를 연결하면 쓸 수 있습니다", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .onSubmit(submit)
                .disabled(!enabled)
            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill").font(Theme.Glyph.large)
            }
            .buttonStyle(.ghost)
            .disabled(!enabled || sending || question.isEmpty)
            .help("보내기")
            .alignmentGuide(.lastTextBaseline) { $0[VerticalAlignment.center] + 4.5 }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s + 2)
        .floatingGlass()
        .padding(Theme.Space.m)
    }

    func submit() {
        guard enabled, !sending, !question.isEmpty else { return }
        send(question)
        text = ""
    }
}

/// Collects an answer's pieces off the main actor; the panel reads the text so far on its own schedule.
final class AnswerStream: Sendable {
    private let buffer = Mutex<String?>(nil)

    var text: String? { buffer.withLock { $0 } }
    func append(_ piece: String) { buffer.withLock { $0 = ($0 ?? "") + piece } }
}
