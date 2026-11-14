import FolioDomain
import Foundation

public enum Effect: String, Codable, Sendable {
    case creates, changes, removes, moves, logs
}

public struct FieldSpec: Codable, Sendable, Equatable {
    public enum Role: Codable, Sendable, Equatable {
        case argument
        case option
        case off(String)
        case new
        case hidden
    }

    public var name: String
    public var help: String
    public var role: Role
    public var type: String
    public var ref: String?
    public var optional: Bool
    public var many: Bool
    public var patch: Bool
    public var defaultValue: String?
    public var cliName: String?
    public var file: String?
    public var filePerItem: Bool
    public var folder: Bool
    public var parsed: String?
    public var parsedForm: String?

    public init(
        name: String, help: String = "", role: Role = .option, type: String, ref: String? = nil, optional: Bool = false, many: Bool = false,
        patch: Bool = false, defaultValue: String? = nil, cliName: String? = nil, file: String? = nil, filePerItem: Bool = false,
        folder: Bool = false,
        parsed: String? = nil, parsedForm: String? = nil
    ) {
        (self.name, self.help, self.role, self.type, self.ref) = (name, help, role, type, ref)
        (self.optional, self.many, self.patch, self.defaultValue) = (optional, many, patch, defaultValue)
        (self.cliName, self.file, self.filePerItem, self.folder) = (cliName, file, filePerItem, folder)
        (self.parsed, self.parsedForm) = (parsed, parsedForm)
    }
}

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

extension JSONValue {
    public init(_ value: some Encodable) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder.folio.encode(value))
    }
}

extension DecodingError {
    public var summary: String {
        let path = { (c: DecodingError.Context) in
            c.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        }
        return switch self {
        case .keyNotFound(let key, let c):
            String(localized: .errorDecodeKeyNotFound(([path(c)] + [key.stringValue]).filter { !$0.isEmpty }.joined(separator: ".")))
        case .typeMismatch(let t, let c): String(localized: .errorDecodeTypeMismatch(path(c), "\(t)"))
        case .valueNotFound(let t, let c): String(localized: .errorDecodeValueNotFound(path(c), "\(t)"))
        case .dataCorrupted(let c): "\(path(c)): \(c.debugDescription)"
        @unknown default: "\(self)"
        }
    }
}

public enum Patch<T: Codable & Sendable & Equatable>: Sendable, Equatable {
    case keep
    case set(T)

    public func apply(_ value: inout T) {
        if case .set(let v) = self { value = v }
    }

    public var value: T? { if case .set(let v) = self { v } else { nil } }

    public static func changed(_ old: T, _ new: T) -> Patch { old == new ? .keep : .set(new) }

    // 빠진 키는 `.keep`, `null`은 `.set(nil)`인데, 합성한 Codable은 둘을 구분하지 못한다.
    public static func decode<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) throws -> Patch {
        c.contains(key) ? .set(try c.decode(T.self, forKey: key)) : .keep
    }

    public func encode<K: CodingKey>(_ c: inout KeyedEncodingContainer<K>, _ key: K) throws {
        if case .set(let v) = self { try c.encode(v, forKey: key) }
    }
}
