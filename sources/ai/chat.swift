import FolioDomain
import Foundation

extension ContextBuilder {
    public static let chatBudgetTokens = 150_000

    public static func rules(_ text: String) -> ContextItem {
        ContextItem(id: "rules", title: "노트 작성 규칙", tier: .userRules, text: text)
    }

    // 경로와 ID를 글에 넣지 않으면 Claude가 어느 파일인지 몰라, 비슷한 노트를 열린 노트로 잘못 짚었다.
    public static func note(id: UUID, title: String, path: String, body: String, images: [ContextItem.Image] = [], open: Bool)
        -> ContextItem
    {
        ContextItem(
            id: "note:\(id)", title: open ? "열린 노트: \(title)" : "노트: \(title)", tier: open ? .focus : .related,
            text: "경로: \(path)\nID: \(id.uuidString)\n\n\(body)", images: images)
    }

    public static func material(path: String, text: String) -> ContextItem {
        ContextItem(id: "material:\(path)", title: "자료: \(path)", tier: .related, text: text)
    }

    // `page`는 사용자와 앱 링크(`#page=N`)가 세는 대로 1부터 센다. 슬라이드의 글만 보내면 그림과 수식이 빠지므로 그림도
    // 함께 보낸다.
    public static func materialPage(id: UUID, path: String, page: Int, text: String, image: ContextItem.Image?) -> ContextItem {
        ContextItem(
            id: "material:\(path)#page=\(page)", title: "자료: \(path) \(page)쪽", tier: .focus,
            text: "경로: \(path)\nID: \(id.uuidString)\n쪽: \(page)\n\n\(text)", images: image.map { [$0] } ?? [])
    }

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

    public static func panes(_ panes: [Pane]) -> ContextItem? {
        guard panes.count > 1 else { return nil }
        let ordered = panes.filter(\.focused) + panes.filter { !$0.focused }
        let lines = ordered.map { pane in
            guard let shows = pane.shows else { return "- (접힘) \(pane.address)" }
            return "- \(pane.focused ? "[초점] " : "")\(shows): \(pane.address)"
        }
        return ContextItem(
            id: "panes", title: "열린 칸 \(panes.count)개", tier: .focus,
            text: "창의 탭에 나란히 열린 칸이다. 초점 칸이 사용자가 지금 보는 칸이다.\n" + lines.joined(separator: "\n"))
    }

    public static func chatItems(
        course: CourseFile, rules: String, panes: ContextItem? = nil, openNote: ContextItem?,
        alsoOpen: [ContextItem] = [], added: [ContextItem], removed: Set<String>, now: Date
    ) -> [ContextItem] {
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
        shown as the answer. To read a lecture or a textbook PDF, skim it first with material_read and titles (page \
        titles, word counts and its outline), then read the text of only the pages you need, and ask for page pictures \
        (images) only where the text says too little: figures, formulas, scans. Read a class's recording with \
        recording_transcript and a note's pictures or handwriting photos with note_images. Each read stops at a limit and \
        says where the next one starts; read on only as far as the question needs.
        """

    static func history(_ message: ChatMessage, superseded: Set<Int> = []) -> String {
        guard let proposals = message.proposals, !proposals.isEmpty else { return message.text }
        let lines = proposals.enumerated().map { i, p in
            let state =
                p.applied == true
                ? "applied"
                : p.failure.map { "the user applied it and it failed: \($0)" }
                    ?? (superseded.contains(i)
                        ? "not applied; superseded by a later proposal" : "not applied; the user has not approved it")
            return "- \(p.command) \(brief(p.input)): \(state)"
        }
        return message.text + "\n\n[Changes proposed in this answer]\n" + lines.joined(separator: "\n")
    }

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

    public func reply(
        to chat: Chat, context: BuiltContext, targets: [String: ProposalTarget] = [:],
        onEvent: (@Sendable (StreamEvent) -> Void)? = nil
    ) async throws -> MessagesResponse {
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
