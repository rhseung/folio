import Foundation

// MARK: Grades

public enum ComponentMenuCommand: ItemCommand {
    case addScore, edit, moveUp, moveDown, remove

    public var group: MenuGroup {
        switch self {
        case .addScore: .start
        case .edit: .edit
        case .moveUp, .moveDown: .arrange
        case .remove: .remove
        }
    }

    public static func commands(addsScore: Bool, index: Int, count: Int) -> [ComponentMenuCommand] {
        var commands: [ComponentMenuCommand] = addsScore ? [.addScore] : []
        commands.append(.edit)
        if index > 0 { commands.append(.moveUp) }
        if index < count - 1 { commands.append(.moveDown) }
        commands.append(.remove)
        return commands
    }
}
