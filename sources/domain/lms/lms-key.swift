import Foundation

public struct LMSKey: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public enum Kind: String, Sendable, CaseIterable {
        case assignment, file, notice
    }

    public var kind: Kind
    public var id: Int

    public init(kind: Kind, id: Int) {
        self.kind = kind
        self.id = id
    }

    public init?(_ text: String) {
        let parts = text.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let kind = Kind(rawValue: String(parts[0])), let id = Int(parts[1]) else { return nil }
        self.init(kind: kind, id: id)
    }

    public var description: String { "\(kind.rawValue):\(id)" }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let key = LMSKey(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not an LMS key: \(text)"))
        }
        self = key
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }

    public static func < (a: LMSKey, b: LMSKey) -> Bool { (a.kind.rawValue, a.id) < (b.kind.rawValue, b.id) }
}
