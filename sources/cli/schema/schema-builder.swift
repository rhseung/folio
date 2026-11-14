import FolioActions
import FolioDomain
import FolioStorage
import Foundation

final class SchemaBuilder {
    var defs: [String: JSONValue] = [:]
    private var building: Set<String> = []

    func schema(_ type: any Decodable.Type) -> JSONValue { schemaOf(type) }

    func inline(_ type: any Decodable.Type) -> JSONValue { sniffing(type) }
    private func sniffing<T: Decodable>(_ type: T.Type) -> JSONValue { sniff(T.self) }

    private func schemaOf<T: Decodable>(_ type: T.Type) -> JSONValue {
        if let hint = T.self as? any SchemaHint.Type { return hint.schema }
        if let e = T.self as? any (CaseIterable & RawRepresentable).Type {
            return .object(["type": "string", "enum": .array(Self.cases(e).map(JSONValue.string))])
        }
        if let a = T.self as? any SniffArray.Type { return .object(["type": "array", "items": schema(a.element)]) }
        if let d = T.self as? any SniffDictionary.Type { return .object(["type": "object", "additionalProperties": schema(d.value)]) }
        if let o = T.self as? any SniffOptional.Type { return schema(o.wrapped) }
        // `CourseSet.Field`와 `SemesterSet.Field`가 한 항목을 나누면 안 된다.
        let name = String(reflecting: T.self).split(separator: ".").dropFirst().joined(separator: ".")
        if defs[name] == nil, !building.contains(name) {
            building.insert(name)
            defs[name] = sniff(T.self)
            building.remove(name)
        }
        return .object(["$ref": .string("#/$defs/\(name)")])
    }

    private func sniff<T: Decodable>(_ type: T.Type) -> JSONValue {
        let first = Probe(builder: self, caseIndex: 0)
        _ = try? T(from: Sniffer(first))
        guard first.caseCount > 1 else { return first.shape }
        let variants =
            [first.shape]
            + (1..<first.caseCount).map { i in
                let p = Probe(builder: self, caseIndex: i)
                _ = try? T(from: Sniffer(p))
                return p.shape
            }
        return .object(["oneOf": .array(variants)])
    }

    static func cases<E: CaseIterable & RawRepresentable>(_ e: E.Type) -> [String] { e.allCases.map { "\($0.rawValue)" } }
    static func firstCase<E: CaseIterable>(_ e: E.Type) -> Any? { e.allCases.first }

    func placeholder<T: Decodable>(_ type: T.Type, probe: Probe) throws -> T {
        if let hint = T.self as? any SchemaHint.Type, let v = hint.example as? T { return v }
        if let e = T.self as? any CaseIterable.Type, let v = Self.firstCase(e) as? T { return v }
        return try T(from: Sniffer(Probe(builder: self, caseIndex: 0)))
    }
}
