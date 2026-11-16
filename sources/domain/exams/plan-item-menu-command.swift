import Foundation

// MARK: Exam plan item

public enum PlanItemMenuCommand: ItemCommand {
    case done(Bool)
    case remove

    public var group: MenuGroup {
        switch self {
        case .done: .state
        case .remove: .remove
        }
    }
}
