import Foundation

public enum RequirementMenuCommand: ItemCommand {
    case showCourses
    case edit, remove

    public var group: MenuGroup {
        switch self {
        case .showCourses: .open
        case .edit: .edit
        case .remove: .remove
        }
    }

    public static var commands: [RequirementMenuCommand] { [.showCourses, .edit, .remove] }
}
