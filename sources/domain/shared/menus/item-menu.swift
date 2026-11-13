import Foundation

public enum MenuGroup: Int, CaseIterable, Comparable, Sendable {
    case open, start, state, edit, arrange, share, remove

    public static func < (a: MenuGroup, b: MenuGroup) -> Bool { a.rawValue < b.rawValue }

    public var band: Int {
        switch self {
        case .open, .start, .state: 0
        case .edit, .arrange, .share: 1
        case .remove: 2
        }
    }
}

public protocol ItemCommand: Hashable, Sendable {
    var group: MenuGroup { get }
}

public enum MenuHost: Hashable, Sendable {
    case elsewhere
    case own
    case unit(UUID)
    case exam(UUID)
    case list

    public var opensItem: Bool { self != .own }

    public var orders: Bool { self == .list }
}

extension Array where Element: ItemCommand {
    // 같은 그룹 안에서는 선언한 순서를 지킨다.
    public func inMenuOrder() -> [Element] {
        enumerated().sorted { ($0.element.group, $0.offset) < ($1.element.group, $1.offset) }.map(\.element)
    }
}
