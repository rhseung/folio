import Foundation

// MARK: Course and semester

public enum CourseMenuCommand: ItemCommand {
    case open
    case record
    case edit
    case moveUp, moveDown
    case share, showInFinder

    public var group: MenuGroup {
        switch self {
        case .open: .open
        case .record: .start
        case .edit: .edit
        case .moveUp, .moveDown: .arrange
        case .share, .showInFinder: .share
        }
    }

    public static func commands(host: MenuHost, recordable: Bool, order: (index: Int, count: Int)?, finder: Bool) -> [CourseMenuCommand] {
        var commands: [CourseMenuCommand] = host.opensItem ? [.open] : []
        if recordable { commands.append(.record) }
        commands.append(.edit)
        if host.orders, let order {
            if order.index > 0 { commands.append(.moveUp) }
            if order.index < order.count - 1 { commands.append(.moveDown) }
        }
        commands.append(.share)
        if finder { commands.append(.showInFinder) }
        return commands.inMenuOrder()
    }
}
