import Foundation

public enum SemesterMenuCommand: ItemCommand {
    case open
    case addCourse
    case fold(open: Bool)
    case share

    public var group: MenuGroup {
        switch self {
        case .open: .open
        case .addCourse: .start
        case .fold: .arrange
        case .share: .share
        }
    }

    public static func commands(host: MenuHost, addsCourse: Bool, folded: Bool?) -> [SemesterMenuCommand] {
        var commands: [SemesterMenuCommand] = host.opensItem ? [.open] : []
        if addsCourse { commands.append(.addCourse) }
        if host.orders, let folded { commands.append(.fold(open: !folded)) }
        commands.append(.share)
        return commands.inMenuOrder()
    }
}
