import FolioActions
import FolioDomain
import SwiftUI

struct AddSemesterSheet: View {
    @State private var model: AddSemesterModel
    @Environment(\.dismiss) private var dismiss
    let created: (UUID?) -> Void

    init(workspace: Workspace, created: @escaping (UUID?) -> Void) {
        _model = State(initialValue: AddSemesterModel(workspace: workspace))
        self.created = created
    }

    var body: some View {
        SheetForm(
            title: String(localized: .semesterAddTitle), confirm: String(localized: .commonAdd), isDisabled: model.exists, note: model.note
        ) {
            FormRow(label: String(localized: .semesterAddYear)) {
                NumberField(value: $model.year, in: 2000...2100, width: 88)
            }
            FormRow(label: String(localized: .semesterAddTerm)) {
                Select(selection: $model.term, options: Term.ordered.map { ($0, $0.label) })
            }
            FormRow(label: String(localized: .semesterStart)) { DateChip(selection: $model.start, showsTime: false) }
            FormRow(label: String(localized: .semesterEnd), last: true) { DateChip(selection: $model.end, showsTime: false) }
        } onConfirm: {
            created(model.add())
            dismiss()
        }
    }
}
