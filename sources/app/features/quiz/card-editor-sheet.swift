import FolioDomain
import SwiftUI

struct CardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: CardEditorModel
    let units: [FolioDomain.Unit]
    let saved: () -> Void

    init(workspace: Workspace, course: LoadedCourse, draft: CardDraft, units: [FolioDomain.Unit], saved: @escaping () -> Void) {
        _model = State(initialValue: CardEditorModel(workspace: workspace, course: course, draft: draft))
        self.units = units
        self.saved = saved
    }

    var body: some View {
        SheetForm(
            title: model.title, confirm: String(localized: .commonSave), disabled: !model.draft.isValid, carded: false,
            deleteTitle: model.deleteTitle,
            onDelete: {
                model.remove {
                    saved()
                    dismiss()
                }
            }
        ) {
            Card {
                FormRow(label: String(localized: .quizUnit)) {
                    SearchSelect(selection: $model.draft.unitId, options: model.unitOptions(units))
                }
                FormRow(label: String(localized: .quizCategory)) {
                    ChoiceMenu(selection: $model.draft.category, options: CardCategory.allCases.map { ($0, $0.label) })
                }
                FormRow(label: String(localized: .quizCardType), last: true) {
                    ChoiceMenu(selection: $model.draft.type, options: CardType.editable.map { ($0, $0.label) })
                }
            }
            FormTextArea(label: String(localized: .quizCardPrompt), text: $model.draft.prompt)
            switch model.draft.type {
            case .choice:
                FormTextArea(
                    label: String(localized: .quizCardOptions), detail: String(localized: .quizCardOnePerLine), text: $model.draft.options)
                Card {
                    FormRow(label: String(localized: .quizCardAnswer), last: true) {
                        ChoiceMenu(
                            selection: $model.draft.answer,
                            options: [("", String(localized: .quizCardChoose))] + model.draft.optionList.map { ($0, $0) })
                    }
                }
            case .trueFalse:
                Card {
                    FormRow(label: String(localized: .quizCardAnswer), last: true) {
                        ChoiceMenu(
                            selection: $model.draft.answer,
                            options: [("", String(localized: .quizCardChoose))] + QuizCard.trueFalseOptions.map { ($0, $0) })
                    }
                }
            default:
                FormTextArea(label: String(localized: .quizModelAnswer), text: $model.draft.answer)
            }
            FormTextArea(
                label: String(localized: .quizCardRubric), detail: String(localized: .quizCardRubricDetail), text: $model.draft.rubric)
        } onConfirm: {
            guard model.saveCard() else { return }
            saved()
            dismiss()
        }
        .confirming($model.pending)
    }
}
