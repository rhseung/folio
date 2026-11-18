import FolioAI
import FolioDomain
import SwiftUI

struct CourseNotesPage: View {
    @Bindable var model: CourseModel
    let course: LoadedCourse

    var body: some View {
        if let note = model.openNoteFile(course) {
            NotesView(
                workspace: model.workspace, course: course, note: note, anchor: model.noteAnchor, insert: $model.noteInsert,
                moves: model.noteMoves)
        } else {
            NoteGalleryView(workspace: model.workspace, course: course, moves: model.noteMoves) { model.show(note: $0) }
        }
    }
}
