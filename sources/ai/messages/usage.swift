import FolioDomain
import Foundation

public struct Usage: Codable, Sendable, Equatable {
    public var input_tokens: Int
    public var output_tokens: Int
    public var cache_creation_input_tokens: Int?
    public var cache_read_input_tokens: Int?

    public init(input_tokens: Int, output_tokens: Int, cache_creation_input_tokens: Int? = nil, cache_read_input_tokens: Int? = nil) {
        self.input_tokens = input_tokens
        self.output_tokens = output_tokens
        self.cache_creation_input_tokens = cache_creation_input_tokens
        self.cache_read_input_tokens = cache_read_input_tokens
    }
}
