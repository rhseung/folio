import FolioDomain
import Foundation

// Wire types for `POST /v1/messages`. Swift has no official Anthropic SDK, so these mirror the documented
// HTTP shapes (anthropic-version 2026-10-21) and nothing more.

public struct CacheControl: Codable, Sendable, Equatable {
    public var type = "ephemeral"
    public init() {}
}

public enum ContentBlock: Codable, Sendable, Equatable {
    case text(String, cache: Bool = false)
    case image(Data, mediaType: String, cache: Bool = false)
    /// Blocks the app doesn't act on (thinking, fallback markers, ...), kept so they can be echoed back unchanged.
    case other(JSONValue)

    enum CodingKeys: String, CodingKey { case type, text, source, cache_control }
    struct ImageSource: Codable { var type = "base64"; var media_type: String; var data: String }

    public func encode(to encoder: any Encoder) throws {
        if case .other(let raw) = self { return try raw.encode(to: encoder) }
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text, let cache):
            try c.encode("text", forKey: .type)
            try c.encode(text, forKey: .text)
            if cache { try c.encode(CacheControl(), forKey: .cache_control) }
        case .image(let data, let mediaType, let cache):
            try c.encode("image", forKey: .type)
            try c.encode(ImageSource(media_type: mediaType, data: data.base64EncodedString()), forKey: .source)
            if cache { try c.encode(CacheControl(), forKey: .cache_control) }
        case .other:
            break
        }
    }

    public init(from decoder: any Decoder) throws {
        let raw = try JSONValue(from: decoder)
        if raw["type"] == .string("text"), case .string(let text)? = raw["text"] {
            self = .text(text)
        } else {
            self = .other(raw)
        }
    }
}

public struct Message: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public var role: Role
    public var content: [ContentBlock]

    public init(role: Role, content: [ContentBlock]) {
        self.role = role
        self.content = content
    }
}

public enum Effort: String, Codable, Sendable {
    case low, medium, high, xhigh, max
}

public struct OutputConfig: Codable, Sendable, Equatable {
    public struct Format: Codable, Sendable, Equatable {
        public var type = "json_schema"
        public var schema: JSONValue
    }

    public var effort: Effort?
    public var format: Format?
}

public struct MessagesRequest: Encodable, Sendable, Equatable {
    public var model: String
    public var max_tokens: Int
    public var system: [ContentBlock]?
    public var messages: [Message]
    public var output_config: OutputConfig?
    /// `"default"`: on a safety refusal the server re-runs the request on Anthropic's recommended fallback model.
    public var fallbacks: String?

    var betas: [String] { fallbacks == nil ? [] : [ClaudeAPI.fallbackBeta] }

    enum CodingKeys: String, CodingKey { case model, max_tokens, system, messages, output_config, fallbacks }
}

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

public struct MessagesResponse: Codable, Sendable, Equatable {
    public var id: String
    /// The model that actually answered; differs from the request after a fallback.
    public var model: String
    public var content: [ContentBlock]
    public var stop_reason: String?
    public var usage: Usage

    public init(id: String, model: String, content: [ContentBlock], stop_reason: String?, usage: Usage) {
        self.id = id
        self.model = model
        self.content = content
        self.stop_reason = stop_reason
        self.usage = usage
    }

    public var text: String {
        content.compactMap { if case .text(let t, _) = $0 { t } else { nil } }.joined()
    }
}

public enum ClaudeError: Error, Equatable {
    case missingAPIKey
    case http(status: Int, body: String)
    /// The model (and its fallback) declined; the content must not be used.
    case refused
    case truncated
    /// Structured output still didn't match the schema after one retry.
    case invalidOutput(String)
}

enum ClaudeAPI {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let version = "2026-10-21"
    static let fallbackBeta = "server-side-fallback-2026-07-01"
}
