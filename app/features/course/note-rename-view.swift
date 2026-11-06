import FolioStorage
import SwiftUI

struct NoteRenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: NoteRenameModel

    init(workspace: Workspace, course: LoadedCourse, note: NoteFile) {
        _model = State(initialValue: NoteRenameModel(workspace: workspace, course: course, note: note))
    }

    var body: some View {
        SheetForm(title: String(localized: .notesRename), confirm: String(localized: .notesRenameConfirm), disabled: !model.canSave, note: model.message) {
            FormRow(label: String(localized: .notesRenameField), last: true) {
                InlineField(String(localized: .notesRenameField), text: $model.name)
            }
        } onConfirm: {
            if model.rename() { dismiss() }
        }
    }
}
