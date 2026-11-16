import Foundation

public enum SessionMenuCommand: ItemCommand {
    case open
    case join
    case openNote(NoteKind)
    case makeReviewNote
    case play(UUID)
    case recordings([UUID])
    case record
    case review(ClassReview)
    case edit
    case unlink(unit: UUID)
    case share
    case remove

    // `default`를 두지 않는다. 그래야 새 명령은 어느 무리에 들지 정할 때까지 컴파일되지 않는다.
    public var group: MenuGroup {
        switch self {
        case .open, .join, .openNote, .makeReviewNote, .play, .recordings: .open
        case .record: .start
        case .review: .state
        case .edit: .edit
        case .unlink: .arrange
        case .share: .share
        case .remove: .remove
        }
    }
}
