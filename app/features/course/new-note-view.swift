import FolioDomain
import SwiftUI

struct NewNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: NewNoteModel
    let created: (UUID) -> Void

    init(workspace: Workspace, course: LoadedCourse, kind: NoteKind, created: @escaping (UUID) -> Void) {
        _model = State(initialValue: NewNoteModel(workspace: workspace, course: course, kind: kind))
        self.created = created
    }

    var body: some View {
        SheetForm(title: String(localized: .notesNewSheet), confirm: String(localized: .commonAdd), disabled: !model.canAdd) {
            FormRow(label: String(localized: .notesFieldTitle)) { InlineField(String(localized: .notesFieldTitleExample), text: $model.title) }
            FormRow(label: String(localized: .notesFieldFormat), detail: model.format == .tex ? String(localized: .notesFieldFormatTex) : nil) {
                Segmented(selection: $model.format, options: model.formatOptions)
            }
            FormRow(label: String(localized: .notesFieldKind), last: model.link == .none) {
                ChoiceMenu(selection: $model.kind, options: model.kindOptions)
            }
            switch model.link {
            case .session:
                FormRow(label: String(localized: .notesFieldSession), detail: String(localized: .notesFieldSessionDetail(model.kind.label)), last: true) {
                    SearchSelect(selection: $model.sessionId, options: model.sessionOptions)
                }
            case .exam:
                FormRow(label: String(localized: .notesFieldExam), last: true) { SearchSelect(selection: $model.examId, options: model.examOptions) }
            case .units:
                FormRow(label: String(localized: .notesFieldUnits), last: true) {
                    SearchMultiSelect(selection: $model.unitIds, options: model.unitOptions, placeholder: String(localized: .commonNone), subtree: model.unitSubtree)
                }
            case .none:
                EmptyView()
            }
        } onConfirm: {
            guard let id = model.add() else { return }
            dismiss()
            created(id)
        }
    }
}
