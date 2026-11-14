import FolioDomain
import SwiftUI

struct ComponentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ComponentModel

    init(workspace: Workspace, course: LoadedCourse, component: GradeComponent) {
        _model = State(initialValue: ComponentModel(workspace: workspace, course: course, component: component))
    }

    var body: some View {
        SheetForm(
            title: model.sheetTitle, confirm: model.confirmTitle, disabled: model.invalid,
            deleteTitle: model.isNew ? nil : String(localized: .componentSheetRemove), onDelete: { model.remove { dismiss() } }
        ) {
            FormRow(label: String(localized: .componentSheetName)) {
                InlineField(String(localized: .componentSheetNameExample), text: $model.name)
            }
            FormRow(label: String(localized: .componentSheetGroup), detail: String(localized: .componentSheetGroupDetail)) {
                InlineField(String(localized: .componentSheetGroupExample), text: $model.group)
            }
            FormRow(label: String(localized: .componentSheetWeight)) {
                HStack(spacing: Theme.Space.s) {
                    TextField(String(localized: .componentSheetWeight), value: $model.weight, format: .number).pill(width: 72)
                    Text("%").foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            FormRow(label: String(localized: .componentSheetAggregation), last: model.aggregation == .single) {
                ChoiceMenu(selection: $model.aggregation, options: model.aggregationOptions)
            }
            if model.count != nil {
                FormRow(label: model.countLabel) {
                    ChoiceMenu(selection: $model.countValue, options: model.countOptions)
                }
            }
            if model.aggregation != .single {
                FormRow(
                    label: String(localized: .componentSheetExpectedCount), detail: String(localized: .componentSheetExpectedCountDetail),
                    last: true
                ) {
                    HStack(spacing: Theme.Space.tight) {
                        TextField(String(localized: .componentSheetUnset), value: $model.expectedCount, format: .number).pill(width: 110)
                        Text(.componentSheetTimesUnit).foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
            }
        } onConfirm: {
            if model.confirm() { dismiss() }
        }
        .confirming($model.pending)
    }
}
