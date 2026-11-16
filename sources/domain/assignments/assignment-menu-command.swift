import Foundation

// MARK: Assignment

public enum AssignmentMenuCommand: ItemCommand {
    case open
    case addFiles
    case status(AssignmentStatus)
    case edit, share
    case showInFinder
    case remove

    public var group: MenuGroup {
        switch self {
        case .open: .open
        case .addFiles: .start
        case .status: .state
        case .edit: .edit
        case .share, .showInFinder: .share
        case .remove: .remove
        }
    }
}
