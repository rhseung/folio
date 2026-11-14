import Foundation

// MARK: Unit

public enum UnitMenuCommand: ItemCommand {
    case open
    case review
    case skipToday
    case addCard
    case moveUp, moveDown
    case share, remove

    public var group: MenuGroup {
        switch self {
        case .open: .open
        case .review, .skipToday, .addCard: .start
        case .moveUp, .moveDown: .arrange
        case .share: .share
        case .remove: .remove
        }
    }
}
