import FolioDomain
import Foundation

public struct ActionSpec: Codable, Sendable, Equatable {
    public var command: String
    public var summary: String
    public var discussion: String
    public var effect: Effect
    public var confirm: String?
    public var done: String
    public var examples: [String]
    public var phrases: [String]
    public var generated: Bool
    public var manualReason: String?
    public var undoable: Bool
    public var fields: [FieldSpec]

    public init(
        command: String, summary: String, discussion: String = "", effect: Effect = .changes, confirm: String? = nil, done: String,
        examples: [String] = [], phrases: [String] = [], generated: Bool = true, manualReason: String? = nil, undoable: Bool = false,
        fields: [FieldSpec] = []
    ) {
        (self.command, self.summary, self.discussion, self.effect, self.confirm) = (command, summary, discussion, effect, confirm)
        (self.done, self.examples, self.phrases, self.generated, self.fields) = (done, examples, phrases, generated, fields)
        (self.manualReason, self.undoable) = (manualReason, undoable)
    }

    public func asks(_ action: some Action) -> Bool {
        guard confirm != nil else { return false }
        if effect == .removes || effect == .moves { return true }
        guard case .object(let o)? = try? JSONValue(action) else { return false }
        return fields.contains { f in f.many && { if case .array(let a)? = o[f.name] { a.count > 1 } else { false } }() }
    }

    public func render(_ template: String, _ action: some Action, ctx: ActionContext) -> String {
        guard case .object(let o)? = try? JSONValue(action) else { return template }
        var out = template
        for f in fields where out.contains("{\(f.name)}") {
            out = out.replacingOccurrences(of: "{\(f.name)}", with: Self.text(o[f.name], ref: f.ref != nil, ctx: ctx))
        }
        return out
    }

    static func text(_ value: JSONValue?, ref: Bool, ctx: ActionContext) -> String {
        switch value {
        case nil, .null?: return ""
        case .string(let s)?:
            guard ref, let id = UUID(uuidString: s) else { return s }
            return ctx.name(of: id) ?? s
        case .bool(let b)?: return b ? String(localized: .valueYes) : String(localized: .valueNo)
        case .number(let n)?: return n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        case .array(let items)?:
            let objects = items.contains { if case .object = $0 { true } else { false } }
            return items.count > 3 || objects
                ? String(localized: .valueCount(items.count)) : items.map { text($0, ref: ref, ctx: ctx) }.joined(separator: ", ")
        case .object?: return ""
        }
    }
}
