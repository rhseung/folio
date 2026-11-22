import FolioDomain
import SwiftUI

struct ProblemEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ProblemEditorModel

    init(workspace: Workspace, course: LoadedCourse, set: UUID, problem: Problem) {
        _model = State(initialValue: ProblemEditorModel(workspace: workspace, course: course, set: set, problem: problem))
    }

    var body: some View {
        SheetForm(
            title: model.title, confirm: String(localized: .commonSave), carded: false, width: Theme.Size.solveSetup,
            deleteTitle: String(localized: .problemsRemove), onDelete: model.remove
        ) {
            TextArea(label: String(localized: .problemsText), text: $model.text)
            Card {
                FormRow(label: String(localized: .problemsFormat)) {
                    SegmentedControl(selection: $model.format, options: model.formatOptions, size: .small)
                }
                if model.picksAnswer {
                    FormRow(label: String(localized: .problemsAnswer)) { Select(selection: $model.answer, options: model.answerOptions) }
                } else if model.hasKeyField {
                    FormRow(label: String(localized: .problemsAnswer)) { InlineField(String(localized: .commonNone), text: $model.answer) }
                }
                FormRow(label: String(localized: .problemsPage)) { InlineField("3", text: $model.page) }  // strings: data, 쪽 번호의 보기
                FormRow(label: String(localized: .problemsSolutionPage)) {
                    InlineField("3", text: $model.solutionPage)  // strings: data, 쪽 번호의 보기
                }
                FormRow(label: String(localized: .problemsUnits), last: true) {
                    MultiCombobox(selection: $model.unitIds, options: model.unitOptions, prompt: String(localized: .commonNone))
                }
            }
            if model.format == .choice {
                TextArea(
                    label: String(localized: .problemsOptions), detail: String(localized: .problemsOptionsDetail), text: $model.options)
            }
            TextArea(label: String(localized: .problemsSolution), text: $model.solution)
        } onConfirm: {
            if model.confirm() { dismiss() }
        }
        .confirming($model.pending)
    }
}
