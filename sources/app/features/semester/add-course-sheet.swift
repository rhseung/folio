import FolioActions
import FolioDomain
import SwiftUI

struct AddCourseSheet: View {
    @State private var model: AddCourseModel
    @Environment(\.dismiss) private var dismiss
    let created: (UUID?) -> Void

    init(workspace: Workspace, semester: Semester, created: @escaping (UUID?) -> Void) {
        _model = State(initialValue: AddCourseModel(workspace: workspace, semester: semester))
        self.created = created
    }

    var body: some View {
        SheetForm(
            title: String(localized: .semesterAddCourseTitle(model.semester.title)), confirm: String(localized: .commonAdd),
            disabled: model.disabled, note: model.note
        ) {
            FormRow(label: String(localized: .semesterAddCourseName)) {
                InlineField(String(localized: .semesterAddCourseNameExample), text: $model.title)
            }
            FormRow(label: String(localized: .semesterAddCourseCode)) {
                SearchSelect(
                    selection: $model.codeId,
                    options: model.codes.map {
                        PickOption(
                            id: Optional($0.id), title: $0.prefix,
                            detail: [$0.department, $0.program].filter { !$0.isEmpty }.joined(separator: " · "))
                    })
                TextField("4207-01", text: $model.number).pill(width: 100)
            }
            FormRow(label: String(localized: .semesterCreditsLabel)) { CreditsField(credits: $model.credits) }
            FormRow(label: String(localized: .semesterAddCourseMode), last: true) {
                ChoiceMenu(selection: $model.mode, options: [GradingMode.relative, .absolute, .passFail].map { ($0, $0.label) })
            }
        } onConfirm: {
            guard !model.disabled else { return }
            created(model.add())
            dismiss()
        }
    }
}
