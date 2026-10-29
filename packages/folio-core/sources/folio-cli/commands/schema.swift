import FolioActions
import FolioDomain
import FolioStorage
import Foundation

/// JSON Schema for action inputs, read off the input types by decoding them with a decoder that answers every
/// question with a placeholder and notes what was asked. That keeps the schema from drifting from the types
/// (docs/SPEC.md "에이전트용 호출"); Swift has no reflection over `Decodable`, and schema libraries need a macro on
/// every domain type.
final class SchemaBuilder {
    var defs: [String: JSONValue] = [:]
    private var building: Set<String> = []

    func schema(_ type: any Decodable.Type) -> JSONValue { schemaOf(type) }

    /// The type's own shape rather than a reference to it, for the actions themselves.
    func inline(_ type: any Decodable.Type) -> JSONValue { sniffing(type) }
    private func sniffing<T: Decodable>(_ type: T.Type) -> JSONValue { sniff(T.self) }

    private func schemaOf<T: Decodable>(_ type: T.Type) -> JSONValue {
        if let hint = T.self as? any SchemaHint.Type { return hint.schema }
        if let e = T.self as? any (CaseIterable & RawRepresentable).Type { return .object(["type": "string", "enum": .array(Self.cases(e).map(JSONValue.string))]) }
        if let a = T.self as? any SniffArray.Type { return .object(["type": "array", "items": schema(a.element)]) }
        if let d = T.self as? any SniffDictionary.Type { return .object(["type": "object", "additionalProperties": schema(d.value)]) }
        if let o = T.self as? any SniffOptional.Type { return schema(o.wrapped) }
        // `CourseSet.Field` and `SemesterSet.Field` must not share one entry.
        let name = String(reflecting: T.self).split(separator: ".").dropFirst().joined(separator: ".")
        if defs[name] == nil, !building.contains(name) {
            building.insert(name)
            defs[name] = sniff(T.self)
            building.remove(name)
        }
        return .object(["$ref": .string("#/$defs/\(name)")])
    }

    /// A struct's fields, or for an enum with payloads (keys listed by `CaseIterable` coding keys) one shape per case.
    private func sniff<T: Decodable>(_ type: T.Type) -> JSONValue {
        let first = Probe(builder: self, caseIndex: 0)
        _ = try? T(from: Sniffer(first))
        guard first.caseCount > 1 else { return first.shape }
        let variants = [first.shape] + (1..<first.caseCount).map { i in
            let p = Probe(builder: self, caseIndex: i)
            _ = try? T(from: Sniffer(p))
            return p.shape
        }
        return .object(["oneOf": .array(variants)])
    }

    static func cases<E: CaseIterable & RawRepresentable>(_ e: E.Type) -> [String] { e.allCases.map { "\($0.rawValue)" } }
    static func firstCase<E: CaseIterable>(_ e: E.Type) -> Any? { e.allCases.first }

    /// A value of `T` to hand back to whoever is decoding, so it carries on to the next field.
    func placeholder<T: Decodable>(_ type: T.Type, probe: Probe) throws -> T {
        if let hint = T.self as? any SchemaHint.Type, let v = hint.example as? T { return v }
        if let e = T.self as? any CaseIterable.Type, let v = Self.firstCase(e) as? T { return v }
        return try T(from: Sniffer(Probe(builder: self, caseIndex: 0)))
    }
}

/// What one decode asked for.
final class Probe {
    let builder: SchemaBuilder
    let caseIndex: Int
    var properties: [String: JSONValue] = [:]
    /// Filled in after they are handed out (an enum case's payload), so read when the shape is.
    var nested: [String: Probe] = [:]
    var required: [String] = []
    var single: JSONValue?
    var caseCount = 0

    init(builder: SchemaBuilder, caseIndex: Int) {
        self.builder = builder
        self.caseIndex = caseIndex
    }

    var shape: JSONValue {
        if let single { return single }
        let all = properties.merging(nested.mapValues(\.shape)) { a, _ in a }
        return .object(["type": "object", "properties": .object(all), "required": .array(required.map(JSONValue.string))])
    }

    func field(_ key: CodingKey, _ schema: JSONValue, required: Bool) {
        properties[key.stringValue] = schema
        if required, !self.required.contains(key.stringValue) { self.required.append(key.stringValue) }
    }
}

struct Sniffer: Decoder {
    let probe: Probe
    init(_ probe: Probe) { self.probe = probe }
    var codingPath: [any CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        KeyedDecodingContainer(Keyed<Key>(probe: probe))
    }
    func unkeyedContainer() throws -> any UnkeyedDecodingContainer { Unkeyed() }
    func singleValueContainer() throws -> any SingleValueDecodingContainer { Single(probe: probe) }

    struct Keyed<Key: CodingKey>: KeyedDecodingContainerProtocol {
        let probe: Probe
        var codingPath: [any CodingKey] = []

        /// Asked only by enums with payloads (and types keeping unknown keys): the case under study.
        var allKeys: [Key] {
            guard let cases = Key.self as? any CaseIterable.Type else { return [] }
            let all = Self.keys(cases).compactMap { $0 as? Key }
            probe.caseCount = all.count
            return all.indices.contains(probe.caseIndex) ? [all[probe.caseIndex]] : []
        }
        static func keys<C: CaseIterable>(_ c: C.Type) -> [Any] { Array(c.allCases) }

        func contains(_ key: Key) -> Bool { true }
        func decodeNil(forKey key: Key) throws -> Bool { false }

        func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
            probe.field(key, probe.builder.schema(T.self), required: true)
            return try probe.builder.placeholder(T.self, probe: probe)
        }
        func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
            probe.field(key, probe.builder.schema(T.self), required: false)
            return nil
        }
        func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
            let inner = Probe(builder: probe.builder, caseIndex: 0)
            probe.nested[key.stringValue] = inner
            if !probe.required.contains(key.stringValue) { probe.required.append(key.stringValue) }
            return KeyedDecodingContainer(Keyed<NestedKey>(probe: inner))
        }
        func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer { Unkeyed() }
        func superDecoder() throws -> any Decoder { Sniffer(probe) }
        func superDecoder(forKey key: Key) throws -> any Decoder { Sniffer(probe) }
    }

    /// Always empty: element types come from the static type instead (`SniffArray`).
    struct Unkeyed: UnkeyedDecodingContainer {
        var codingPath: [any CodingKey] = []
        var count: Int? { 0 }
        var isAtEnd: Bool { true }
        var currentIndex = 0
        mutating func decodeNil() throws -> Bool { true }
        mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
            throw DecodingError.valueNotFound(T.self, .init(codingPath: [], debugDescription: "empty"))
        }
        mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
            throw DecodingError.valueNotFound(NestedKey.self, .init(codingPath: [], debugDescription: "empty"))
        }
        mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer { self }
        mutating func superDecoder() throws -> any Decoder {
            throw DecodingError.valueNotFound(Decoder.self, .init(codingPath: [], debugDescription: "empty"))
        }
    }

    struct Single: SingleValueDecodingContainer {
        let probe: Probe
        var codingPath: [any CodingKey] = []
        func decodeNil() -> Bool { false }
        func decode(_ type: Bool.Type) throws -> Bool { probe.single = ["type": "boolean"]; return false }
        func decode(_ type: String.Type) throws -> String { probe.single = ["type": "string"]; return "" }
        func decode(_ type: Double.Type) throws -> Double { probe.single = ["type": "number"]; return 0 }
        func decode(_ type: Int.Type) throws -> Int { probe.single = ["type": "integer"]; return 0 }
        func decode<T: Decodable>(_ type: T.Type) throws -> T {
            probe.single = probe.builder.schema(T.self)
            return try probe.builder.placeholder(T.self, probe: probe)
        }
    }
}

protocol SniffArray { static var element: any Decodable.Type { get } }
extension Array: SniffArray where Element: Decodable { static var element: any Decodable.Type { Element.self } }
extension Set: SniffArray where Element: Decodable { static var element: any Decodable.Type { Element.self } }
protocol SniffDictionary { static var value: any Decodable.Type { get } }
extension Dictionary: SniffDictionary where Key == String, Value: Decodable { static var value: any Decodable.Type { Value.self } }
protocol SniffOptional { static var wrapped: any Decodable.Type { get } }
extension Optional: SniffOptional where Wrapped: Decodable { static var wrapped: any Decodable.Type { Wrapped.self } }

/// Leaf types: their schema, and a value that decodes.
protocol SchemaHint {
    static var schema: JSONValue { get }
    static var example: Any { get }
}

extension String: SchemaHint { static var schema: JSONValue { ["type": "string"] }; static var example: Any { "" } }
extension Bool: SchemaHint { static var schema: JSONValue { ["type": "boolean"] }; static var example: Any { false } }
extension Int: SchemaHint { static var schema: JSONValue { ["type": "integer"] }; static var example: Any { 0 } }
extension Int64: SchemaHint { static var schema: JSONValue { ["type": "integer"] }; static var example: Any { Int64(0) } }
extension Double: SchemaHint { static var schema: JSONValue { ["type": "number"] }; static var example: Any { 0.0 } }
extension UUID: SchemaHint { static var schema: JSONValue { ["type": "string", "format": "uuid"] }; static var example: Any { UUID() } }
extension Date: SchemaHint { static var schema: JSONValue { ["type": "string", "format": "date-time"] }; static var example: Any { Date() } }
extension Data: SchemaHint { static var schema: JSONValue { ["type": "string", "contentEncoding": "base64"] }; static var example: Any { Data() } }
extension URL: SchemaHint { static var schema: JSONValue { ["type": "string", "format": "uri"] }; static var example: Any { URL(filePath: "/") } }
extension JSONValue: SchemaHint { static var schema: JSONValue { [:] }; static var example: Any { JSONValue.null } }
extension LocalDate: SchemaHint {
    static var schema: JSONValue { ["type": "string", "format": "date"] }
    static var example: Any { LocalDate(year: 2026, month: 1, day: 1)! }
}
/// Written as one string, so the decoder can't see its cases.
extension Aggregation: SchemaHint {
    static var schema: JSONValue { ["type": "string", "description": "sum, mean, single, dropLowest:<n>, bestOf:<n>"] }
    static var example: Any { Aggregation.sum }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByDictionaryLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(Dictionary(elements) { a, _ in a }) }
}

/// `folio actions --schema`: one JSON value with every action's command, summary, and input schema.
/// The decoded shape with what only the declaration knows: which kind of item a field names (`x-folio-ref`, a UUID
/// or a name), and that a `Patch` field may be left out.
func declaredInput(_ spec: ActionSpec, _ sniffed: JSONValue) -> JSONValue {
    guard case .object(var o) = sniffed, case .object(var props)? = o["properties"], case .array(let required)? = o["required"] else { return sniffed }
    for f in spec.fields {
        guard case .object(var p)? = props[f.name] else { continue }
        if let kind = f.ref {
            let one: JSONValue = ["type": "string", "x-folio-ref": .string(kind)]
            p = f.many ? ["type": "array", "items": one] : ["type": "string", "x-folio-ref": .string(kind)]
        }
        let help = [f.help, f.patch && f.optional ? "null이면 지운다" : ""].filter { !$0.isEmpty }.joined(separator: ". ")
        if !help.isEmpty { p["description"] = .string(help) }
        props[f.name] = .object(p)
    }
    let optional = Set(spec.fields.filter { $0.patch || $0.role == .new }.map(\.name))
    o["properties"] = .object(props)
    o["required"] = .array(required.filter { if case .string(let k) = $0 { !optional.contains(k) } else { true } })
    return .object(o)
}

func actionSchemas() -> JSONValue {
    let builder = SchemaBuilder()
    let refNote = "항목을 가리키는 필드(course, semester, session, exam, unit, material, component, assignment, set, note)는 UUID와 이름(EC4207, 9주차-1, Quiz1)을 모두 받는다. 새 항목의 id는 빼면 만들어진다. x-folio-ref가 있는 필드는 그 종류의 항목을 가리킨다. NotePath는 노트를 과목 폴더 기준 경로로 가리키고, 노트 이름도 받는다. asks가 true인 액션은 --yes 없이 터미널이 아니면 종료 코드 5로 멈춘다."
    let actions = Actions.all.map { type -> JSONValue in
        let spec = type.spec
        guard !spec.done.isEmpty else {
            return ["command": .string(type.command), "type": .string(String(describing: type)), "input": builder.inline(type)]
        }
        return [
            "command": .string(type.command),
            "type": .string(String(describing: type)),
            "summary": .string(spec.summary),
            "effect": .string(spec.effect.rawValue),
            "asks": .bool(spec.effect == .removes || spec.effect == .moves),
            "input": declaredInput(spec, builder.inline(type)),
        ]
    }
    return [
        "description": .string(refNote),
        "run": "folio run <command> --input '<JSON>'",
        "result": [
            "type": "object",
            "properties": ["action": ["type": "string"], "dryRun": ["type": "boolean"], "made": ["type": "string", "format": "uuid"],
                           "changes": ["type": "array"]],
        ],
        "actions": .array(actions),
        "$defs": .object(builder.defs),
    ]
}
