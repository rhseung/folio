import FolioMarkdown
import Foundation
import Observation

struct NoteOutlineFit: Equatable {
    var besideSplit: Bool
    var besideOne: Bool

    init(width: CGFloat) {
        besideSplit = width >= NotePanes.sideBySide + Theme.Size.noteOutline
        besideOne = width >= NoteLook.measure + Theme.Size.noteOutline
    }

    func docks(_ shown: NotePanes.Mode) -> Bool { shown == .split ? besideSplit : besideOne }
}
