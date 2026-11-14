import Foundation

// MARK: Quiz

public enum CardMenuCommand: ItemCommand {
    case solveWrong
    case edit, share, remove

    public var group: MenuGroup {
        switch self {
        case .solveWrong: .start
        case .edit: .edit
        case .share: .share
        case .remove: .remove
        }
    }

    public static func commands(solvesWrong: Bool) -> [CardMenuCommand] {
        (solvesWrong ? [.solveWrong] : []) + [.edit, .share, .remove]
    }
}
