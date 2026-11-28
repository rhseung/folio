import FolioDomain
import SwiftUI

struct CardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: CardEditorModel
    let saved: () -> Void

    init(workspace: Workspace, course: LoadedCourse, draft: CardDraft, saved: @escaping () -> Void = {}) {
        _model = State(initialValue: CardEditorModel(workspace: workspace, course: course, draft: draft))
        self.saved = saved
    }

    func remove() {
        model.remove {
            saved()
            dismiss()
        }
    }

    var body: some View {
        SheetForm(
            title: model.title, confirm: String(localized: .commonSave), isDisabled: !model.draft.isValid, carded: false,
            deleteTitle: model.deleteTitle,
            onDelete: remove
        ) {
            Card {
                FormRow(label: String(localized: .cardsKind)) {
                    SegmentedControl(selection: $model.draft.kind, options: model.kindOptions, size: .small)
                }
                if model.draft.kind == .trueFalse {
                    FormRow(label: String(localized: .cardsAnswer)) {
                        SegmentedControl(selection: $model.draft.answer, options: model.answerOptions, size: .small)
                    }
                }
                if !model.sections.isEmpty {
                    FormRow(label: String(localized: .cardsNoteSection)) {
                        Select(selection: $model.section, options: model.sectionOptions)
                    }
                }
                FormRow(label: String(localized: .cardsUnit), last: !model.sourceChanged) {
                    Combobox(selection: $model.draft.unitId, options: model.unitOptions)
                }
                if model.sourceChanged {
                    FormRow(
                        label: String(localized: .cardsSourceChanged), detail: String(localized: .cardsSourceChangedDetail), warns: true,
                        last: true
                    ) {
                        Button(.cardsSourceRefresh) { model.refreshFromSource() }.buttonStyle(.secondary).disabled(!model.canRefresh)
                    }
                }
            }
            TextArea(label: model.frontLabel, text: $model.draft.front)
            TextArea(label: model.backLabel, text: $model.draft.back)
        } onConfirm: {
            guard model.confirm() else { return }
            saved()
            dismiss()
        }
        .confirming($model.pending)
    }
}
