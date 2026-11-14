import FolioDomain
import SwiftUI

struct ScoreEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ScoreEntryModel

    init(workspace: Workspace, course: LoadedCourse, entry: ScoreEntry) {
        _model = State(initialValue: ScoreEntryModel(workspace: workspace, course: course, entry: entry))
    }

    var body: some View {
        SheetForm(
            title: model.sheetTitle, confirm: model.confirmTitle, disabled: !model.valid,
            deleteTitle: model.isNew ? nil : String(localized: .scoreSheetRemove), onDelete: { model.remove { dismiss() } }
        ) {
            if !model.isNew {
                FormRow(label: String(localized: .scoreSheetComponent)) {
                    ChoiceMenu(selection: $model.componentId, options: model.componentOptions)
                }
            }
            FormRow(label: String(localized: .scoreSheetSource), detail: String(localized: .scoreSheetSourceDetail)) {
                SearchSelect(selection: Binding(get: { model.source }, set: { model.pick($0) }), options: model.sourceOptions)
            }
            if model.hasTitle {
                FormRow(label: String(localized: .scoreSheetTitle)) {
                    InlineField(String(localized: .scoreSheetTitleExample), text: $model.title)
                }
            }
            FormRow(label: String(localized: .scoreSheetScore)) {
                HStack(spacing: Theme.Space.s) {
                    TextField(String(localized: .scoreSheetScore), text: $model.score).pill(width: 72)
                    Text("/").foregroundStyle(Theme.Palette.textTertiary)
                    TextField(String(localized: .scoreSheetMax), text: $model.max).pill(width: 72)
                }
            }
            FormRow(label: String(localized: .scoreSheetMeanAndStdDev), detail: model.meanDetail) {
                HStack(spacing: Theme.Space.s) {
                    TextField(String(localized: .scoreSheetMean), text: $model.mean).pill(width: 72)
                    Text("±").foregroundStyle(Theme.Palette.textTertiary)
                    TextField(String(localized: .scoreSheetStdDev), text: $model.stdDev).pill(width: 72)
                }
            }
            FormRow(label: String(localized: .scoreSheetCounts), detail: String(localized: .scoreSheetCountsDetail), last: true) {
                ChoiceMenu(
                    selection: $model.excused,
                    options: [(false, String(localized: .scoreSheetCounts)), (true, String(localized: .courseGradesExcused))])
            }
        } onConfirm: {
            if model.confirm() { dismiss() }
        }
        .confirming($model.pending)
    }
}
