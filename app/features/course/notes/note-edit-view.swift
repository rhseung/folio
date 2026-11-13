import FolioDomain
import FolioStorage
import SwiftUI

struct NoteEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: NoteEditModel

    init(workspace: Workspace, course: LoadedCourse, note: NoteFile, moves: MoveUndo? = nil) {
        _model = State(initialValue: NoteEditModel(workspace: workspace, course: course, note: note, moves: moves))
    }

    var body: some View {
        SheetForm(
            title: String(localized: .notesEdit), confirm: String(localized: .commonSave), disabled: !model.canSave, note: model.message
        ) {
            FormRow(label: String(localized: .notesRenameField)) {
                InlineField(String(localized: .notesRenameField), text: $model.name)
            }
            FormRow(label: String(localized: .notesEditFolder), last: !model.choosesMath && model.pdfName == nil) {
                ChoiceMenu(selection: $model.folder, options: model.folderOptions)
            }
            if model.choosesMath {
                FormRow(label: String(localized: .notesMathSyntax), last: model.pdfName == nil) {
                    Segmented(selection: $model.math, options: MathSyntax.allCases.map { ($0, $0.label) })
                }
            }
            if let pdf = model.pdfName {
                FormRow(label: String(localized: .notesRenamePdf), detail: model.pdfDetail, last: true) {
                    Text(pdf).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1).truncationMode(.middle)
                }
            }
        } onConfirm: {
            if model.apply() { dismiss() }
        }
    }
}
