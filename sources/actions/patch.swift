import FolioDomain
import Foundation

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
