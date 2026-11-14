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
            title: String(localized: .semesterAddTitle), confirm: String(localized: .commonAdd), disabled: model.exists, note: model.note
        ) {
            FormRow(label: String(localized: .semesterAddYear)) {
                ScrubField(
                    value: Binding(get: { Double(model.year) }, set: { model.year = Int($0.rounded()) }), range: 2000...2100, step: 1,
                    width: 88)
            }
            FormRow(label: String(localized: .semesterAddTerm)) {
                ChoiceMenu(selection: $model.term, options: AddSemesterModel.terms.map { ($0, $0.label) })
            }
            FormRow(label: String(localized: .semesterStart)) { DateChip(date: $model.start, showsTime: false) }
            FormRow(label: String(localized: .semesterEnd), last: true) { DateChip(date: $model.end, showsTime: false) }
        } onConfirm: {
            created(model.add())
            dismiss()
        }
    }
}
