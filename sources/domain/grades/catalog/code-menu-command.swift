import Foundation

public enum CodeMenuCommand: ItemCommand {
    case edit, remove

    public var group: MenuGroup {
        switch self {
        case .edit: .edit
        case .remove: .remove
        }
    }

    public static var commands: [CodeMenuCommand] { [.edit, .remove] }
}
