import Foundation

// MARK: Exam

public enum ExamMenuCommand: ItemCommand {
    case open
    case summary
    case addFiles
    case edit, share, remove

    public var group: MenuGroup {
        switch self {
        case .open, .summary: .open
        case .addFiles: .start
        case .edit: .edit
        case .share: .share
        case .remove: .remove
        }
    }
}
