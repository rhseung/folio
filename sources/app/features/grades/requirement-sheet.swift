import FolioDomain
import SwiftUI

struct RequirementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: RequirementEditModel
    @State private var removing = false

    init(workspace: Workspace, category: RequirementCategory) {
        _model = State(initialValue: RequirementEditModel(workspace: workspace, category: category))
    }

    var body: some View {
        SheetForm(
            title: model.title, confirm: String(localized: .commonSave), disabled: model.draft.name.isEmpty, carded: false, width: 560,
            deleteTitle: model.isNew ? nil : String(localized: .requirementsRemove), onDelete: { removing = true }
        ) {
            Block(String(localized: .requirementsFieldCategory)) {
                Card {
                    FormRow(label: String(localized: .requirementsFieldName)) {
                        InlineField(String(localized: .requirementsFieldNameExample), text: $model.draft.name)
                    }
                    FormRow(label: String(localized: .requirementsFieldGroup), detail: String(localized: .requirementsFieldGroupDetail)) {
                        InlineField(String(localized: .requirementsFieldGroupExample), text: $model.draft.group)
                    }
                    FormRow(label: String(localized: .requirementsFieldParent)) {
                        SearchSelect(selection: $model.draft.parentId, options: model.parentOptions)
                    }
                    FormRow(label: String(localized: .requirementsFieldProgram), detail: String(localized: .requirementsFieldProgramDetail))
                    {
                        ChoiceMenu(selection: $model.draft.programId, options: model.programOptions)
                    }
                    FormRow(
                        label: String(localized: .requirementsFieldMajor), detail: String(localized: .requirementsFieldMajorDetail),
                        last: true
                    ) { Switch(isOn: $model.draft.isMajor) }
                }
            }
            Block(String(localized: .requirementsCriteria), note: String(localized: .requirementsCriteriaNote)) {
                Card {
                    FormRow(label: String(localized: .requirementsFieldMinCredits)) {
                        TextField(String(localized: .requirementsNone), value: $model.draft.minCredits, format: .number).pill(width: 72)
                    }
                    FormRow(
                        label: String(localized: .requirementsFieldMaxCredits),
                        detail: String(localized: .requirementsFieldMaxCreditsDetail)
                    ) {
                        TextField(String(localized: .requirementsNone), value: $model.draft.maxCredits, format: .number).pill(width: 72)
                    }
                    FormRow(
                        label: String(localized: .requirementsFieldMinCount), detail: String(localized: .requirementsFieldMinCountDetail)
                    ) {
                        TextField(String(localized: .requirementsNone), value: $model.draft.minCount, format: .number).pill(width: 72)
                    }
                    FormRow(
                        label: String(localized: .requirementsFieldSharedCap), detail: String(localized: .requirementsFieldSharedCapDetail),
                        last: true
                    ) {
                        TextField(String(localized: .requirementsNone), value: $model.draft.maxSharedCredits, format: .number).pill(
                            width: 72)
                    }
                }
            }
            FormTextArea(
                label: String(localized: .requirementsFieldRule),
                text: Binding(get: { model.draft.rule ?? "" }, set: { model.draft.rule = $0.isEmpty ? nil : $0 }))
        } onConfirm: {
            model.confirm()
            dismiss()
        }
        .confirmationDialog(RequirementsModel.removeTitle(model.draft), isPresented: $removing) {
            Button(.commonDelete, role: .destructive) {
                model.remove()
                dismiss()
            }
        } message: {
            Text(.requirementsRemoveMessage)
        }
    }
}
