import FolioDomain
import Foundation

extension ContextBuilder {
    /// Context budget for the chat panel, well under the model's window so the conversation itself still fits.
    public static let chatBudgetTokens = 150_000

    public static func rules(_ text: String) -> ContextItem {
        ContextItem(id: "rules", title: "노트 작성 규칙", tier: .userRules, text: text)
    }

    /// `path` is relative to the course folder. It and the ID go in the text so Claude knows which file the note is and
    /// can name it to Folio's tools; without them it guessed, and took a similar note for the open one.
    public static func note(id: UUID, title: String, path: String, body: String, images: [ContextItem.Image] = [], open: Bool) -> ContextItem {
        ContextItem(id: "note:\(id)", title: open ? "열린 노트: \(title)" : "노트: \(title)", tier: open ? .focus : .related,
                    text: "경로: \(path)\nID: \(id.uuidString)\n\n\(body)", images: images)
    }

    public static func material(path: String, text: String) -> ContextItem {
        ContextItem(id: "material:\(path)", title: "자료: \(path)", tier: .related, text: text)
    }

    /// One page of a PDF the user is looking at, asked about from the file view (#120). `page` is 1-based, as the user
    /// and the app link (`#page=N`) count it. The picture goes too: a slide's text alone loses its figures and formulas.
    public static func materialPage(id: UUID, path: String, page: Int, text: String, image: ContextItem.Image?) -> ContextItem {
        ContextItem(id: "material:\(path)#page=\(page)", title: "자료: \(path) \(page)쪽", tier: .focus,
                    text: "경로: \(path)\nID: \(id.uuidString)\n쪽: \(page)\n\n\(text)", images: image.map { [$0] } ?? [])
    }

    /// A pane of the window's tab (#62), as the chat panel sees it: the panel is the window's one, so it has to say
    /// which pane is meant by "this". `shows` is nil for a folded pane, which goes by its address alone.
    public struct Pane: Sendable, Equatable {
        public var address: String
        public var shows: String?
        public var focused: Bool

        public init(address: String, shows: String?, focused: Bool) {
            self.address = address
            self.shows = shows
            self.focused = focused
        }
    }

    /// The tab's panes, the focused one first and marked, then the rest left to right. Nil for a lone pane, which
    /// the open note or page already is.
    public static func panes(_ panes: [Pane]) -> ContextItem? {
        guard panes.count > 1 else { return nil }
        let ordered = panes.filter(\.focused) + panes.filter { !$0.focused }
        let lines = ordered.map { pane in
            guard let shows = pane.shows else { return "- (접힘) \(pane.address)" }
            return "- \(pane.focused ? "[초점] " : "")\(shows): \(pane.address)"
        }
        return ContextItem(id: "panes", title: "열린 칸 \(panes.count)개", tier: .focus,
                           text: "창의 탭에 나란히 열린 칸이다. 초점 칸이 사용자가 지금 보는 칸이다.\n" + lines.joined(separator: "\n"))
    }

    /// `openNote` is the focused pane's note (or the first open one), `alsoOpen` the notes the other panes show.
    public static func chatItems(course: CourseFile, rules: String, panes: ContextItem? = nil, openNote: ContextItem?,
                                 alsoOpen: [ContextItem] = [], added: [ContextItem], removed: Set<String>, now: Date) -> [ContextItem] {
        var items = [courseSummary(course, now: now), Self.rules(rules)]
        if let panes { items.append(panes) }
        if let openNote { items.append(openNote) }
        for item in alsoOpen where !items.contains(where: { $0.id == item.id }) { items.append(item) }
        for item in added where !items.contains(where: { $0.id == item.id }) { items.append(item) }
        return items.filter { !removed.contains($0.id) }
    }
}

extension ClaudeClient {
    static let chatInstructions = """
    You are a study assistant inside Folio, a university student's course notebook. Use the course context you are \
    given and say so when the answer is not in it. Answer in Korean unless asked otherwise. Write math as LaTeX in $…$ \
    and $$…$$, one display equation per block. When writing note content, follow the note-writing rules and Folio's \
    note syntax: callouts `> [!type] title` (`[!type]-` starts folded), links `[[note:<ID>|name]]` and \
    `[[material:<ID>#page=N|name]]`, diagrams in ```mermaid fences. Before writing an SVG figure or a widget, read \
    note_format once and look at your drafts with note_figure_render or note_widget_render. Your earlier \
    answers end with the state of the changes they proposed; rely on it rather than guessing whether a change was made. \
    Put the whole answer in your final message. Write nothing between tool calls: only the final message is kept and \
    shown as the answer.
    """

    /// An earlier answer as sent back: its text, then what became of each change it proposed. Without the second
    /// part Claude can't tell a change the user never approved from one that failed.
    /// `superseded` holds the positions of proposals a later answer replaced, which the panel no longer offers.
    static func history(_ message: ChatMessage, superseded: Set<Int> = []) -> String {
        guard let proposals = message.proposals, !proposals.isEmpty else { return message.text }
        let lines = proposals.enumerated().map { i, p in
            let state = p.applied == true ? "applied"
                : p.failure.map { "the user applied it and it failed: \($0)" }
                ?? (superseded.contains(i) ? "not applied; superseded by a later proposal" : "not applied; the user has not approved it")
            return "- \(p.command) \(brief(p.input)): \(state)"
        }
        return message.text + "\n\n[Changes proposed in this answer]\n" + lines.joined(separator: "\n")
    }

    /// The proposal's input with long values such as a note's text cut short, so the history doesn't repeat them whole.
    static func brief(_ input: JSONValue) -> String {
        func cut(_ v: JSONValue) -> JSONValue {
            switch v {
            case .string(let s) where s.count > 80: .string(String(s.prefix(80)) + "… (\(s.count) characters)")
            case .object(let o): .object(o.mapValues(cut))
            case .array(let a): .array(a.map(cut))
            default: v
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: (try? encoder.encode(cut(input))) ?? Data(), as: UTF8.self)
    }

    /// The context goes in the system prompt (stable part, cached) and in front
    /// of the newest question only; earlier turns are sent as plain text. `targets` is what
    /// `Chat.supersededProposals` decides by, which FolioAI can't read from the actions itself.
    public func reply(to chat: Chat, context: BuiltContext, targets: [String: ProposalTarget] = [:],
                      onEvent: (@Sendable (StreamEvent) -> Void)? = nil) async throws -> MessagesResponse {
        guard let last = chat.messages.last, last.role == .user else { throw ClaudeError.invalidOutput("no question to answer") }
        let superseded = chat.supersededProposals(targets: targets)
        var messages = chat.messages.dropLast().map { m in
            let replaced = Set(superseded.filter { $0.message == m.id }.map(\.index))
            return Message(role: m.role == .user ? .user : .assistant, content: [.text(Self.history(m, superseded: replaced))])
        }
        messages.append(Message(role: .user, content: context.userBlocks + [.text(last.text)]))
        return try await text(.chat, system: [.text(Self.chatInstructions)] + context.system, messages: messages, onEvent: onEvent)
    }
}

public struct MonthlyUsage: Sendable, Equatable {
    public var year: Int
    public var month: Int
    public var requests: Int
    /// Input including cache writes and reads.
    public var inputTokens: Int
    public var outputTokens: Int
    /// Dollars; events of a model missing from the price table count as zero.
    public var cost: Double
}

extension APIUsageEvent {
    public static func monthly(_ events: [(at: Date, event: APIUsageEvent)], calendar: Calendar) -> [MonthlyUsage] {
        var months: [DateComponents: MonthlyUsage] = [:]
        for (at, e) in events {
            let key = calendar.dateComponents([.year, .month], from: at)
            var m = months[key] ?? MonthlyUsage(year: key.year!, month: key.month!, requests: 0, inputTokens: 0, outputTokens: 0, cost: 0)
            m.requests += 1
            m.inputTokens += e.usage.input_tokens + (e.usage.cache_creation_input_tokens ?? 0) + (e.usage.cache_read_input_tokens ?? 0)
            m.outputTokens += e.usage.output_tokens
            m.cost += e.cost ?? 0
            months[key] = m
        }
        return months.values.sorted { ($0.year, $0.month) > ($1.year, $1.month) }
    }
}
