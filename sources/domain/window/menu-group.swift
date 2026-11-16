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
