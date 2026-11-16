import Foundation

public enum MaterialRoute: Hashable, Sendable {
    case direct
    case pages
    case session(UUID)
    case unit(UUID)
    case folder
}
