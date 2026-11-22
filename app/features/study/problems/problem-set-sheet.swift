import FolioDomain
import SwiftUI

struct ProblemSetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ProblemSetDraftModel

    init(workspace: Workspace, course: LoadedCourse) {
        _model = State(initialValue: ProblemSetDraftModel(workspace: workspace, course: course))
    }

    var body: some View {
        SheetForm(title: String(localized: .problemSetAddTitle), confirm: String(localized: .commonAdd), isDisabled: !model.canAdd) {
            FormRow(label: String(localized: .problemSetFieldTitle)) {
                InlineField(String(localized: .problemSetFieldTitleExample), text: $model.title)
            }
            FormRow(label: String(localized: .problemSetSource)) { Select(selection: $model.source, options: model.sourceOptions) }
            FormRow(label: String(localized: .problemSetSheet), detail: model.sheetDetail) {
                Combobox(selection: $model.problemId, options: model.pdfOptions)
            }
            FormRow(label: String(localized: .problemSetSolution)) { Combobox(selection: $model.solutionId, options: model.pdfOptions) }
            FormRow(label: String(localized: .problemSetNumbers), detail: model.numbersDetail) {
                InlineField("1-10", text: $model.numbers)  // strings: data, 번호 범위의 보기
            }
            FormRow(label: String(localized: .problemSetUnits), detail: String(localized: .problemSetUnitsDetail), last: true) {
                MultiCombobox(selection: $model.unitIds, options: model.unitOptions, prompt: String(localized: .commonNone))
            }
        } onConfirm: {
            if model.add() { dismiss() }
        }
    }
}
