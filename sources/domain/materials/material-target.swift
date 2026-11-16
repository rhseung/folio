import Foundation

public enum MaterialTarget: Hashable, Sendable {
    case session(UUID)
    case unit(UUID)
    case exam(UUID)
}
