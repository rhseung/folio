import FolioDomain
import Foundation

// `POST /v1/messages`의 전송 타입이다. Swift용 공식 Anthropic SDK가 없으므로 문서화된 HTTP 형식(anthropic-version
// 2026-10-21)만 그대로 옮긴다.

public struct CacheControl: Codable, Sendable, Equatable {
    public var type = "ephemeral"
    public init() {}
}
