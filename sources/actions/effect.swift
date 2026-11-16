import FolioDomain
import Foundation

public enum Effect: String, Codable, Sendable {
    case creates, changes, removes, moves, logs
}
