import Foundation

// MARK: Exam plan row

public enum PlanItemMenuCommand: ItemCommand {
    case advance
    case postpone
    case pickDay
    case done(Bool)
    case remove

    public var group: MenuGroup {
        switch self {
        case .advance, .postpone, .pickDay: .start
        case .done: .state
        case .remove: .remove
        }
    }
}
