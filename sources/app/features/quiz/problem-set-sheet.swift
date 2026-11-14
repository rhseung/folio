import FolioDomain
import SwiftUI

struct ProblemSetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ProblemSetDraftModel

    init(workspace: Workspace, course: LoadedCourse) {
        _model = State(initialValue: ProblemSetDraftModel(workspace: workspace, course: course))
    }

    var body: some View {
        let pdfOptions = model.pdfOptions
        SheetForm(title: String(localized: .quizProblemsAddTitle), confirm: String(localized: .commonAdd), disabled: !model.canAdd) {
            FormRow(label: String(localized: .quizProblemsFieldTitle)) {
                InlineField(String(localized: .quizProblemsFieldTitleExample), text: $model.title)
            }
            FormRow(label: String(localized: .quizProblemsSheet), detail: model.sheetDetail) {
                SearchSelect(selection: $model.problemId, options: pdfOptions)
            }
            FormRow(label: String(localized: .quizProblemsSolution)) { SearchSelect(selection: $model.solutionId, options: pdfOptions) }
            FormRow(label: String(localized: .quizProblemsFieldNumbers), detail: model.numbersDetail) {
                TextField("1-10", text: $model.numbers).pill(width: 160)
            }
            FormRow(label: String(localized: .quizUnit), detail: String(localized: .quizProblemsUnitsDetail), last: true) {
                SearchMultiSelect(selection: $model.unitIds, options: model.course.unitOptions, placeholder: String(localized: .commonNone))
            }
        } onConfirm: {
            model.add()
            dismiss()
        }
    }
}
