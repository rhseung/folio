import Foundation

// MARK: Unit

public enum UnitMenuCommand: ItemCommand {
    case open
    case solve
    // 지금 "다 함"인지 들고 있어서 메뉴가 표시와 해제 중 하나를 그린다.
    case done(Bool)
    case addCard
    case moveUp, moveDown
    case share, remove

    public var group: MenuGroup {
        switch self {
        case .open: .open
        case .solve, .done, .addCard: .start
        case .moveUp, .moveDown: .arrange
        case .share: .share
        case .remove: .remove
        }
    }
}
