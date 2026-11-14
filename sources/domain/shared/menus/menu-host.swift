import Foundation

public enum MenuHost: Hashable, Sendable {
    case elsewhere
    case own
    case unit(UUID)
    case exam(UUID)
    case list

    public var opensItem: Bool { self != .own }

    public var orders: Bool { self == .list }
}
