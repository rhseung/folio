import FolioActions
import FolioDomain
import SwiftUI

struct ExamEditor: View {
    @State private var model: ExamEditorModel
    @Environment(\.dismiss) private var dismiss

    init(workspace: Workspace, course: LoadedCourse, exam: Exam) {
        _model = State(initialValue: ExamEditorModel(workspace: workspace, course: course, exam: exam))
    }

    var body: some View {
        let units = model.units
        let course = model.course
        SheetForm(title: model.title, confirm: model.confirm, isDisabled: model.disabled, note: model.note, carded: false, width: 560) {
            Block(String(localized: .examsEditorExam)) {
                Card {
                    FormRow(label: String(localized: .examsEditorName), last: course.file.components.isEmpty) {
                        InlineField(model.namePrompt, text: $model.draft.title)
                    }
                    if !course.file.components.isEmpty {
                        FormRow(label: String(localized: .examsEditorComponent), last: true) {
                            Select(selection: $model.draft.componentId, options: model.components)
                        }
                    }
                }
            }
            Block(String(localized: .examsEditorWhenWhere)) {
                Card {
                    FormRow(
                        label: String(localized: .examsEditorWhen),
                        detail: model.endsBeforeStart ? String(localized: .examsEditorEndsBeforeStart) : nil
                    ) {
                        if model.draft.start == nil {
                            Button(.examsEditorSetDate) { model.setDefaultStart() }
                                .buttonStyle(.ghost)
                        } else {
                            DateChip(selection: Binding(get: { model.draft.start ?? .now }, set: model.setStart))
                            Text("–").foregroundStyle(Theme.Palette.textTertiary)
                            if let end = model.endMinute {
                                TimePicker(selection: Binding(get: { end }, set: model.setEnd))
                                Button {
                                    model.setEnd(nil)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.pointing(.plain)).foregroundStyle(Theme.Palette.textTertiary).help(Text(.examsEditorClearEnd))
                            } else {
                                Button(.examsEditorAddEnd) { model.addEnd() }.buttonStyle(.ghost)
                            }
                        }
                    }
                    FormRow(label: String(localized: .examsEditorLocation)) {
                        TextField(String(localized: .examsEditorLocationExample), text: $model.draft.location).pill(
                            width: Theme.Size.textField)
                    }
                    FormRow(label: String(localized: .examsEditorAllowed), last: true) {
                        InlineField(String(localized: .examsEditorAllowedExample), text: $model.draft.allowed)
                    }
                }
            }
            Block(String(localized: .examsScope)) {
                Card {
                    FormRow(label: String(localized: .examsEditorUnits)) {
                        MultiCombobox(
                            selection: $model.draft.scopeUnitIds,
                            options: units.map { SelectOption(id: $0.unit.id, label: $0.unit.title, depth: $0.depth) },
                            prompt: String(localized: units.isEmpty ? .examsEditorNoUnits : .examsEditorPick),
                            subtree: { UnitTree.subtree(of: $0, in: course.file.units) }
                        )
                        .disabled(units.isEmpty)
                    }
                    FormRow(label: String(localized: .examsEditorScopeText), last: true) {
                        InlineField(String(localized: .examsEditorScopeTextExample), text: $model.draft.scopeText)
                    }
                }
            }
            TextArea(label: String(localized: .examsEditorMemo), text: $model.draft.memo)
        } onConfirm: {
            if model.apply() { dismiss() }
        }
    }
}
