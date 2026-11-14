import Foundation

public enum ProblemMenuCommand: ItemCommand {
    case openSheet
    case record
    case units

    public var group: MenuGroup {
        switch self {
        case .openSheet: .open
        case .record: .start
        case .units: .state
        }
    }

    public static func commands(hasSheet: Bool, hasUnits: Bool) -> [ProblemMenuCommand] {
        (hasSheet ? [.openSheet] : []) + [.record] + (hasUnits ? [.units] : [])
    }
}
