import FolioDomain
import FolioStorage
import SwiftUI

struct NoteSheetRequest {
    let id = UUID()
    let course: UUID
    let note: NoteFile
    var moves: MoveUndo?
}
