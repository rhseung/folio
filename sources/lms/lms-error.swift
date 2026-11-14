import FolioDomain
import Foundation
import Security

public enum LMSError: Error, Equatable, Sendable {
    case needsLogin
    case refused
    case http(Int)
}
