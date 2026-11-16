import Foundation

// MARK: Material

public enum MaterialMenuCommand: ItemCommand {
    case open
    case openWithDefault
    case openInEditor
    case openPDF(UUID)
    case edit
    case move
    case unlink(MenuHost)
    case share, showInFinder
    case remove
    case relink, untrack

    public var group: MenuGroup {
        switch self {
        case .open, .openWithDefault, .openInEditor, .openPDF: .open
        case .edit, .relink: .edit
        case .move, .unlink: .arrange
        case .share, .showInFinder: .share
        case .remove, .untrack: .remove
        }
    }
}
