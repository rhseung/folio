import Foundation

public enum Aggregation: Hashable, Sendable, Codable {
    case sum
    case mean
    case dropLowest(Int)
    case bestOf(Int)
    case single

    var stored: String {
        switch self {
        case .sum: "sum"
        case .mean: "mean"
        case .single: "single"
        case .dropLowest(let n): "dropLowest:\(n)"
        case .bestOf(let n): "bestOf:\(n)"
        }
    }

    init?(stored: String) {
        let parts = stored.split(separator: ":")
        switch (parts.first, parts.count == 2 ? Int(parts[1]) : nil) {
        case ("sum", nil): self = .sum
        case ("mean", nil): self = .mean
        case ("single", nil): self = .single
        case ("dropLowest", let n?): self = .dropLowest(n)
        case ("bestOf", let n?): self = .bestOf(n)
        default: return nil
        }
    }

    public init(from decoder: any Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let value = Aggregation(stored: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown aggregation \(s)"))
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(stored)
    }
}
