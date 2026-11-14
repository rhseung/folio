import FolioDomain
import Foundation

public enum ClaudeError: Error, Equatable {
    case missingAPIKey
    case http(status: Int, body: String)
    case refused
    case truncated
    case invalidOutput(String)
}
