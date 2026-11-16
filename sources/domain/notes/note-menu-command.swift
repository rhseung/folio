import Foundation

// MARK: Note

public enum NoteMenuCommand: ItemCommand {
    case open
    case openPDF
    case build
    case review(ClassReview)
    case edit
    case move
    case share, showInFinder
    case remove

    public var group: MenuGroup {
        switch self {
        case .open, .openPDF: .open
        case .build: .start
        case .review: .state
        case .edit: .edit
        case .move: .arrange
        case .share, .showInFinder: .share
        case .remove: .remove
        }
    }

    public static func commands(host: MenuHost, builtPDF: Bool, builds: Bool, review: ClassReview?, finder: Bool) -> [NoteMenuCommand] {
        var commands: [NoteMenuCommand] = host.opensItem ? [.open] : []
        if builtPDF { commands.append(.openPDF) }
        if builds { commands.append(.build) }
        if let review, review == .writing || review == .written { commands.append(.review(review)) }
        commands += [.edit, .move, .share]
        if finder { commands.append(.showInFinder) }
        commands.append(.remove)
        return commands.inMenuOrder()
    }
}
