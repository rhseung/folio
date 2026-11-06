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

    public static func chatItems(course: CourseFile, rules: String, openNote: ContextItem?, added: [ContextItem],
                                 removed: Set<String>, now: Date) -> [ContextItem] {
        var items = [courseSummary(course, now: now), Self.rules(rules)]
        if let openNote { items.append(openNote) }
        for item in added where !items.contains(where: { $0.id == item.id }) { items.append(item) }
        return items.filter { !removed.contains($0.id) }
    }
}

extension ClaudeClient {
    static let chatInstructions = """
    You are a study assistant inside Folio, a university student's course notebook. Use the course context you are \
    given and say so when the answer is not in it. Answer in Korean unless asked otherwise. Write math as LaTeX in $…$ \
    and $$…$$, one display equation per block. When writing note content, follow the note-writing rules. Your earlier \
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
    /// of the newest question only; earlier turns are sent as plain text. `targets` is `Chat.supersededProposals`'s map
    /// of the fields that pick each command's item.
    public func reply(to chat: Chat, context: BuiltContext, targets: [String: [String]] = [:],
                      onEvent: (@Sendable (StreamEvent) -> Void)? = nil) async throws -> MessagesResponse {
        guard let last = chat.messages.last, last.role == .user else { throw ClaudeError.invalidOutput("no question to answer") }
        let superseded = chat.supersededProposals(arguments: targets)
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
