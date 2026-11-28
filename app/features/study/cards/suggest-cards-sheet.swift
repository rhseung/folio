import FolioDomain
import SwiftUI

struct SuggestCardsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @State private var model: SuggestCardsModel
    let saved: () -> Void

    init(workspace: Workspace, course: LoadedCourse, unit: FolioDomain.Unit, note: UUID? = nil, saved: @escaping () -> Void = {}) {
        _model = State(initialValue: SuggestCardsModel(workspace: workspace, course: course, unit: unit, note: note))
        self.saved = saved
    }

    var body: some View {
        SheetForm(title: model.title, confirm: model.confirmTitle, isDisabled: !model.canConfirm, note: model.footnote, carded: false) {
            if !model.hasKey {
                Card { MissingKeyNotice().padding(Theme.Space.m) }
            } else if model.candidates.isEmpty {
                Block(String(localized: .cardsSuggestMaterial)) { Card { materials } }
                Block(String(localized: .cardsSuggestFormat)) { Card { options } }
            } else {
                Card { picked }
            }
        } onConfirm: {
            guard model.confirm() else { return }
            saved()
            dismiss()
        }
    }

    // 재료는 하나만 고른다. 쪽 구간이 없는 재료는 고를 수 없고, 왜 없는지를 둘째 줄이 말한다.
    @ViewBuilder var materials: some View {
        let choices = model.choices
        ForEach(Array(choices.enumerated()), id: \.element.id) { i, choice in
            let on = model.material == choice.material
            Button {
                model.material = choice.material
            } label: {
                CardRow(last: i == choices.count - 1) {
                    LineIcon(symbol: on ? "checkmark.circle" : "circle", filled: on)
                        .foregroundStyle(on ? accent.color : Theme.Palette.textTertiary).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(choice.title).lineLimit(1)
                        Text(choice.detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.pointing(.plain))
            .disabled(!choice.isAvailable)
            .opacity(choice.isAvailable ? 1 : Theme.Opacity.disabled)
            .accessibilityAddTraits(on ? .isSelected : [])
        }
    }

    @ViewBuilder var options: some View {
        FormRow(label: String(localized: .cardsKind)) {
            SegmentedControl(selection: $model.kinds, options: model.kindOptions, size: .small)
        }
        FormRow(label: String(localized: .cardsSuggestCount), last: model.busy == false && model.failure == nil) {
            Select(selection: $model.count, options: model.countOptions)
        }
        if model.busy {
            CardRow(last: model.failure == nil) {
                ProgressView().controlSize(.small)
                Text(.cardsSuggestBusy).foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        if let failure = model.failure {
            CardRow(last: true) { Text(failure).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.danger) }
        }
    }

    var picked: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(model.candidates.enumerated()), id: \.element.id) { i, card in
                    let on = model.kept.contains(card.id)
                    Button {
                        model.toggle(card)
                    } label: {
                        CardRow(last: i == model.candidates.count - 1) {
                            LineIcon(symbol: on ? "checkmark.circle" : "circle", filled: on)
                                .foregroundStyle(on ? accent.color : Theme.Palette.textTertiary).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                StudyText(text: card.front).lineLimit(4)
                                StudyText(text: card.backLine).lineLimit(3)
                                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                            }
                            Spacer(minLength: 0)
                            if card.kind == .trueFalse { Badge(card.kind.label) }
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
}
