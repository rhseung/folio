import FolioDomain
import Foundation

public struct MessagesRequest: Encodable, Sendable, Equatable {
    public var model: String
    public var max_tokens: Int
    public var system: [ContentBlock]?
    public var messages: [Message]
    public var output_config: OutputConfig?
    public var fallbacks: String?

    var betas: [String] { fallbacks == nil ? [] : [ClaudeAPI.fallbackBeta] }

    enum CodingKeys: String, CodingKey { case model, max_tokens, system, messages, output_config, fallbacks }
}
