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
                FormRow(label: String(localized: .cardsUnit), last: true) {
                    Combobox(selection: $model.draft.unitId, options: model.unitOptions)
                }
            }
            TextArea(label: String(localized: .cardsFront), text: $model.draft.front)
            TextArea(label: String(localized: .cardsBack), text: $model.draft.back)
        } onConfirm: {
            guard model.confirm() else { return }
            saved()
            dismiss()
        }
        .confirming($model.pending)
    }
}
