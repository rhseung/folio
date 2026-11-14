import FolioDomain
import Foundation

enum ClaudeAPI {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let version = "2026-10-21"
    static let fallbackBeta = "server-side-fallback-2026-07-01"
}
