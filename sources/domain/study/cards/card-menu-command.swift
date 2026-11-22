import Foundation

public enum CardMenuCommand: ItemCommand {
    case flip, edit, share, remove

    public var group: MenuGroup {
        switch self {
        case .flip: .start
        case .edit: .edit
        case .share: .share
        case .remove: .remove
        }
    }

    public static let all: [CardMenuCommand] = [.flip, .edit, .share, .remove]
}
