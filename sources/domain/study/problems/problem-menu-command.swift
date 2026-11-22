import Foundation

public enum ProblemMenuCommand: ItemCommand {
    case openPage, solve, edit, remove

    public var group: MenuGroup {
        switch self {
        case .openPage: .open
        case .solve: .start
        case .edit: .edit
        case .remove: .remove
        }
    }

    public static func commands(hasPage: Bool) -> [ProblemMenuCommand] {
        (hasPage ? [.openPage] : []) + [.solve, .edit, .remove]
    }
}
