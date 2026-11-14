import FolioDomain
import Foundation

public struct ModelPricing: Sendable, Equatable {
    public var input: Double
    public var output: Double
    public var cacheRead: Double

    public static let table: [String: ModelPricing] = [
        "claude-opus-5-5": ModelPricing(input: 4, output: 20, cacheRead: 0.2),
        "claude-haiku-5-5": ModelPricing(input: 0.1, output: 0.5, cacheRead: 0.01),
    ]

    public func cost(of usage: Usage) -> Double {
        let write = Double(usage.cache_creation_input_tokens ?? 0) * input * 1.25
        let read = Double(usage.cache_read_input_tokens ?? 0) * cacheRead
        return (Double(usage.input_tokens) * input + Double(usage.output_tokens) * output + write + read) / 1_000_000
    }
}
