import Foundation

public enum ProblemSetMenuCommand: ItemCommand {
    case openSheet, openSolution, share, remove

    public var group: MenuGroup {
        switch self {
        case .openSheet, .openSolution: .open
        case .share: .share
        case .remove: .remove
        }
    }

    public static func commands(hasSheet: Bool, hasSolution: Bool) -> [ProblemSetMenuCommand] {
        (hasSheet ? [.openSheet] : []) + (hasSolution ? [.openSolution] : []) + [.share, .remove]
    }
}
