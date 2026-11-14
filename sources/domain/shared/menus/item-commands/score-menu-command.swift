import Foundation

public enum ScoreMenuCommand: ItemCommand {
    case counts(Bool)
    case edit, remove

    public var group: MenuGroup {
        switch self {
        case .counts: .state
        case .edit: .edit
        case .remove: .remove
        }
    }

    public static func commands(excused: Bool) -> [ScoreMenuCommand] { [.counts(!excused), .edit, .remove] }
}
