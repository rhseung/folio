import FolioDomain
import Foundation

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
