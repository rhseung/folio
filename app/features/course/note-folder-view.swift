import FolioStorage
import SwiftUI

struct NoteFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: NoteFolderModel

    init(workspace: Workspace, course: LoadedCourse, note: NoteFile) {
        _model = State(initialValue: NoteFolderModel(workspace: workspace, course: course, note: note))
    }

    var body: some View {
        SheetForm(title: String(localized: .notesFolderTitle), confirm: String(localized: .notesFolderConfirm), disabled: !model.canSave,
                  note: model.message) {
            FormRow(label: String(localized: .notesFolderField), last: true) {
                InlineField(String(localized: .notesFolderPrompt), text: $model.name)
            }
        } onConfirm: {
            if model.move() { dismiss() }
        }
    }
}
