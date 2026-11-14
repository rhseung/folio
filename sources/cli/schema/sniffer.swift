import FolioActions
import FolioDomain
import FolioStorage
import Foundation

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
        func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<
            NestedKey
        > {
            let inner = Probe(builder: probe.builder, caseIndex: 0)
            probe.nested[key.stringValue] = inner
            if !probe.required.contains(key.stringValue) { probe.required.append(key.stringValue) }
            return KeyedDecodingContainer(Keyed<NestedKey>(probe: inner))
        }
        func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer { Unkeyed() }
        func superDecoder() throws -> any Decoder { Sniffer(probe) }
        func superDecoder(forKey key: Key) throws -> any Decoder { Sniffer(probe) }
    }

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
