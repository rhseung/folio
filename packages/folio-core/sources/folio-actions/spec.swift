import FolioDomain
import Foundation

/// What an action does to the data, for whoever runs it: removing and moving always ask first.
public enum Effect: String, Codable, Sendable {
    case creates, changes, removes, moves, logs
}

public struct FieldSpec: Codable, Sendable, Equatable {
    public enum Role: Codable, Sendable, Equatable {
        case argument
        case option
        /// A Bool that defaults to true, turned off by the flag of this name.
        case off(String)
        /// The id of the item the action makes: hidden on the CLI and made when left out.
        case new
        /// In the JSON input only.
        case hidden
    }

    public var name: String
    public var help: String
    public var role: Role
    /// The innermost value type as written, e.g. `LocalDate`, or `UUID` for an id.
    public var type: String
    /// The kind of item an id field points at, e.g. `Course` for `Course.ID`.
    public var ref: String?
    public var optional: Bool
    public var many: Bool
    /// `Patch<T>`: left out means unchanged.
    public var patch: Bool
    /// The default as Swift source, e.g. `.other`.
    public var defaultValue: String?
    /// `@CLIName`: the option's name on the CLI, when it isn't the field's.
    public var cliName: String?
    /// `@FromFile`: the CLI takes a path, shown as this value name, and reads the value from that file.
    public var file: String?
    /// `@FromFile(perItem: true)`: a list read one file per item.
    public var filePerItem: Bool
    /// `@Folder`: a folder path, made absolute on the CLI.
    public var folder: Bool
    /// `@Parsed`: the value name of the text the CLI reads into the value, and how that text is written.
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

/// Everything about an action that isn't its `run`: its command, help, effect, the text people see, and its inputs.
/// `@Action` writes it from the declaration; the CLI commands, `run`, the schema and the app's confirmations read it.
public struct ActionSpec: Codable, Sendable, Equatable {
    public var command: String
    public var summary: String
    public var discussion: String
    public var effect: Effect
    /// Asked before running; `{field}` is replaced by the field's value, or the name of the item it points at.
    public var confirm: String?
    /// Shown after running, with the same placeholders.
    public var done: String
    public var examples: [String]
    /// Words people use for it, for `folio help <하고 싶은 일>`.
    public var phrases: [String]
    /// False when the CLI command is written by hand.
    public var generated: Bool
    /// Why the command is written by hand (`cli: .manual(reason:)`).
    public var manualReason: String?
    /// The id it reports as `made` is a batch in moves.jsonl, which `cleanup undo` reverts.
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

    /// Removing and moving always ask; anything else with a confirmation asks only for more than one item at once.
    public func asks(_ action: some Action) -> Bool {
        guard confirm != nil else { return false }
        if effect == .removes || effect == .moves { return true }
        guard case .object(let o)? = try? JSONValue(action) else { return false }
        return fields.contains { f in f.many && { if case .array(let a)? = o[f.name] { a.count > 1 } else { false } }() }
    }

    /// `template` with each `{field}` filled in. Ids show the item's name, looked up before the action runs so the
    /// name of an item it removes still shows.
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
            // Objects have no name of their own, so a list of them is told by its count.
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
    /// Where the input went wrong, as a dotted path, for people and agents fixing it.
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

/// A field of a `set` action: left out, it stays as it is. For an optional field, JSON `null` (CLI `none`) clears it.
public enum Patch<T: Codable & Sendable & Equatable>: Sendable, Equatable {
    case keep
    case set(T)

    public func apply(_ value: inout T) {
        if case .set(let v) = self { value = v }
    }

    public var value: T? { if case .set(let v) = self { v } else { nil } }

    /// `.set(new)` when it differs from `old`: a sheet that holds a whole value sends only what the user changed.
    public static func changed(_ old: T, _ new: T) -> Patch { old == new ? .keep : .set(new) }

    // A missing key is `.keep` and `null` is `.set(nil)`, which synthesized Codable can't tell apart.
    public static func decode<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) throws -> Patch {
        c.contains(key) ? .set(try c.decode(T.self, forKey: key)) : .keep
    }

    public func encode<K: CodingKey>(_ c: inout KeyedEncodingContainer<K>, _ key: K) throws {
        if case .set(let v) = self { try c.encode(v, forKey: key) }
    }
}
