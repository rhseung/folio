import FolioDomain
import SwiftUI

struct NewMaterialFileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: NewMaterialFileModel
    let created: (UUID) -> Void

    init(workspace: Workspace, course: LoadedCourse, folder: String?, created: @escaping (UUID) -> Void) {
        _model = State(initialValue: NewMaterialFileModel(workspace: workspace, course: course, folder: folder))
        self.created = created
    }

    var body: some View {
        SheetForm(title: String(localized: .materialsNewTitle), confirm: String(localized: .materialsNewConfirm), disabled: !model.canCreate,
                  note: String(localized: .materialsNewNote)) {
            FormRow(label: String(localized: .materialsNewFolder)) {
                ChoiceMenu(selection: $model.folder, options: model.folderOptions)
            }
            FormRow(label: String(localized: .materialsNewName), detail: model.refusal, last: true) {
                InlineField(String(localized: .materialsNewNameExample), text: $model.name)
            }
        } onConfirm: {
            guard let id = model.create() else { return }
            dismiss()
            created(id)
        }
    }
}
