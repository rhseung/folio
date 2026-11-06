import FolioStorage
import SwiftUI

struct NoteRenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: NoteRenameModel

    init(workspace: Workspace, course: LoadedCourse, note: NoteFile, moves: MoveUndo? = nil) {
        _model = State(initialValue: NoteRenameModel(workspace: workspace, course: course, note: note, moves: moves))
    }

    var body: some View {
        SheetForm(title: String(localized: .notesRename), confirm: String(localized: .notesRenameConfirm), disabled: !model.canSave, note: model.message) {
            FormRow(label: String(localized: .notesRenameField), last: model.pdfName == nil) {
                InlineField(String(localized: .notesRenameField), text: $model.name)
            }
            if let pdf = model.pdfName {
                FormRow(label: String(localized: .notesRenamePdf), detail: model.pdfDetail, last: true) {
                    Text(pdf).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1).truncationMode(.middle)
                }
            }
        } onConfirm: {
            if model.rename() { dismiss() }
        }
    }
}
