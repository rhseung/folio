import FolioDomain
import Foundation

public enum ContentBlock: Codable, Sendable, Equatable {
    case text(String, cache: Bool = false)
    case image(Data, mediaType: String, cache: Bool = false)
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
