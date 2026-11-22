import FolioDomain
import SwiftUI

struct SuggestCardsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @State private var model: SuggestCardsModel
    let saved: () -> Void

    init(workspace: Workspace, course: LoadedCourse, unit: FolioDomain.Unit, saved: @escaping () -> Void = {}) {
        _model = State(initialValue: SuggestCardsModel(workspace: workspace, course: course, unit: unit))
        self.saved = saved
    }

    var body: some View {
        SheetForm(title: model.title, confirm: model.confirmTitle, isDisabled: !model.canConfirm, note: model.note) {
            if !model.hasKey {
                MissingKeyNotice().padding(Theme.Space.m)
            } else if model.candidates.isEmpty {
                FormRow(label: String(localized: .cardsSuggestCount), last: model.busy == false && model.failure == nil) {
                    Select(selection: $model.count, options: model.countOptions)
                }
                if model.busy {
                    CardRow(last: model.failure == nil) {
                        ProgressView().controlSize(.small); Text(.cardsSuggestBusy).foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                if let failure = model.failure {
                    CardRow(last: true) { Text(failure).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.danger) }
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(model.candidates.enumerated()), id: \.element.id) { i, card in
                            let on = model.kept.contains(card.id)
                            Button {
                                model.toggle(card)
                            } label: {
                                CardRow(last: i == model.candidates.count - 1) {
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(
                                        on ? accent.color : Theme.Palette.textTertiary
                                    ).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                        StudyText(text: card.front).lineLimit(4)
                                        StudyText(text: card.back).lineLimit(3)
                                            .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.pointing(.plain))
                        }
                    }
                }
                .overflowFade(.vertical)
                .frame(maxHeight: Theme.Size.cardDrafts)
            }
        } onConfirm: {
            guard model.confirm() else { return }
            saved()
            dismiss()
        }
    }
}
