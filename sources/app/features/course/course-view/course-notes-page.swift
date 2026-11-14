import FolioAI
import FolioDomain
import SwiftUI

struct CourseNotesPage: View {
    @Bindable var model: CourseModel
    let course: LoadedCourse
    @Environment(\.columnFolded) private var folded

    var body: some View {
        if folded, model.openNote == nil {
            ScrollView {
                NoteList(workspace: model.workspace, course: course, selection: $model.openNote, moves: model.noteMoves)
                    .padding(.horizontal, Theme.Inset.panel)
                    .padding(.vertical, Theme.Space.l)
                    .clearOfColumnButtons(inset: Theme.Space.l)
            }
            .overflowFade(.vertical)
        } else {
            NotesView(
                workspace: model.workspace, course: course, selection: model.openNote, anchor: model.noteAnchor, insert: $model.noteInsert,
                moves: model.noteMoves)
        }
    }
}
