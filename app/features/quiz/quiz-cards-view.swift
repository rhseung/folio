import FolioDomain
import SwiftUI

struct QuizCardsView: View {
    let course: LoadedCourse
    @Bindable var model: QuizModel

    var body: some View {
        Page {
            PageHeader(title: String(localized: .quizCardsTitle), subtitle: model.cardsSubtitle(course))
            if course.outline.isEmpty { EmptyLine(String(localized: .quizCardsNoUnits)) }
            ForEach(model.cardGroups(course)) { group in
                if let root = group.root {
                    Block(title: root.title, note: String(localized: .quizCardCount(group.count)), trailing: { addMenu(root) }) { Card { rows(group.entries) } }
                        .contextMenu { addItems(root) }
                } else {
                    Card { rows(group.entries) }
                }
            }
        }
        .sheet(item: $model.editing) { draft in
            CardEditorSheet(workspace: model.workspace, course: course, draft: draft, units: course.file.units) { model.load(course) }
        }
        .confirmationDialog(String(localized: .quizCardRemoveConfirm),
                            isPresented: Binding(get: { model.removingCard != nil }, set: { if !$0 { model.removingCard = nil } })) {
            Button(.commonDelete, role: .destructive) { model.removeCard(in: course) }
        } message: {
            Text(.quizCardRemoveMessage)
        }
    }

    func rows(_ entries: [QuizModel.Entry]) -> some View {
        ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
            let last = i == entries.count - 1
            switch entry {
            case .unit(let unit, let depth, let n):
                CardRow(last: last) {
                    Text(unit.title).font(n > 0 ? Theme.Typeface.bodyStrong : Theme.Typeface.body).lineLimit(1)
                    Text(model.unitCardsText(n)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    Spacer(minLength: Theme.Space.m)
                    addMenu(unit)
                }
                .padding(.leading, CGFloat(depth) * Theme.Space.xl)
                .contextMenu { addItems(unit) }
            case .card(let card, let depth):
                CardRow(last: last) {
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(markdown(card.prompt)).lineLimit(2)
                        Text(model.detail(card))
                            .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    }
                    Spacer(minLength: Theme.Space.m)
                    if model.isOpen(card) { Chip(String(localized: .quizWrong), tone: .danger) }
                }
                .padding(.leading, CGFloat(depth) * Theme.Space.xl)
                .opens { model.editing = CardDraft(card) }
                .help(Text(.quizCardEdit))
                .contextMenu {
                    Button(.commonEdit) { model.editing = CardDraft(card) }
                    Divider()
                    Button(.commonDeleteEllipsis, role: .destructive) { model.removingCard = card }
                }
            }
        }
    }

    @ViewBuilder func addItems(_ unit: FolioDomain.Unit) -> some View {
        Button(.quizCardsAddManual) { model.editing = CardDraft(unitId: unit.id) }
        Button(.quizCardsAddClaude) { model.generating = unit }
    }

    func addMenu(_ unit: FolioDomain.Unit) -> some View {
        Menu { addItems(unit) } label: { Image(systemName: "plus") }
            .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.borderless).pointingHand().fixedSize()
            .foregroundStyle(Theme.Palette.textSecondary)
            .help(Text(.quizCardsAddHelp(unit.title)))
    }
}

struct CardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: CardEditorModel
    let units: [FolioDomain.Unit]
    let saved: () -> Void
    @State private var confirmingDelete = false

    init(workspace: Workspace, course: LoadedCourse, draft: CardDraft, units: [FolioDomain.Unit], saved: @escaping () -> Void) {
        _model = State(initialValue: CardEditorModel(workspace: workspace, course: course, draft: draft))
        self.units = units
        self.saved = saved
    }

    var body: some View {
        SheetForm(title: model.title, confirm: String(localized: .commonSave), disabled: !model.draft.isValid, carded: false,
                  deleteTitle: model.deleteTitle, onDelete: { confirmingDelete = true }) {
            Card {
                FormRow(label: String(localized: .quizUnit)) { SearchSelect(selection: $model.draft.unitId, options: model.unitOptions(units)) }
                // "유형" is the category, as the solve filter and the statistics call it (docs/SPEC.md "풀기 설정").
                FormRow(label: String(localized: .quizCategory)) { ChoiceMenu(selection: $model.draft.category, options: CardCategory.allCases.map { ($0, $0.label) }) }
                FormRow(label: String(localized: .quizCardType), last: true) { ChoiceMenu(selection: $model.draft.type, options: CardType.editable.map { ($0, $0.label) }) }
            }
            FormTextArea(label: String(localized: .quizCardPrompt), text: $model.draft.prompt, height: 80)
            switch model.draft.type {
            case .choice:
                FormTextArea(label: String(localized: .quizCardOptions), detail: String(localized: .quizCardOnePerLine), text: $model.draft.options, height: 70)
                Card {
                    FormRow(label: String(localized: .quizCardAnswer), last: true) {
                        ChoiceMenu(selection: $model.draft.answer, options: [("", String(localized: .quizCardChoose))] + model.draft.optionList.map { ($0, $0) })
                    }
                }
            case .trueFalse:
                Card {
                    FormRow(label: String(localized: .quizCardAnswer), last: true) {
                        ChoiceMenu(selection: $model.draft.answer, options: [("", String(localized: .quizCardChoose))] + QuizCard.trueFalseOptions.map { ($0, $0) })
                    }
                }
            default:
                FormTextArea(label: String(localized: .quizModelAnswer), text: $model.draft.answer, height: 80)
            }
            FormTextArea(label: String(localized: .quizCardRubric), detail: String(localized: .quizCardRubricDetail), text: $model.draft.rubric, height: 56)
        } onConfirm: {
            guard model.saveCard() else { return }
            saved()
            dismiss()
        }
        .confirmationDialog(String(localized: .quizCardRemoveConfirm), isPresented: $confirmingDelete) {
            Button(.commonDelete, role: .destructive) {
                model.remove()
                saved()
                dismiss()
            }
        } message: {
            Text(.quizCardRemoveMessage)
        }
    }
}

struct GenerateCardsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @State private var model: GenerateCardsModel
    let saved: () -> Void

    init(workspace: Workspace, course: LoadedCourse, unit: FolioDomain.Unit, saved: @escaping () -> Void) {
        _model = State(initialValue: GenerateCardsModel(workspace: workspace, course: course, unit: unit))
        self.saved = saved
    }

    var body: some View {
        SheetForm(title: model.title, confirm: model.confirmTitle, disabled: !model.canConfirm, note: model.note) {
            if !model.hasKey {
                MissingKeyNotice().padding(Theme.Space.m)
            } else if model.candidates.isEmpty {
                FormRow(label: String(localized: .quizGenerateCount)) { ChoiceMenu(selection: $model.count, options: model.countOptions) }
                FormRow(label: String(localized: .quizCardType), last: model.busy == false && model.failure == nil) {
                    ChoiceMenu(selection: $model.type, options: model.typeOptions)
                }
                if model.busy {
                    CardRow(last: model.failure == nil) { ProgressView().controlSize(.small); Text(.quizGenerateBusy).foregroundStyle(Theme.Palette.textSecondary) }
                }
                if let failure = model.failure { CardRow(last: true) { Text(failure).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.danger) } }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(model.candidates.enumerated()), id: \.element.id) { i, card in
                            let on = model.kept.contains(card.id)
                            Button { model.toggle(card) } label: {
                                CardRow(last: i == model.candidates.count - 1) {
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? accent.color : Theme.Palette.textTertiary)
                                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                        Text(markdown(card.prompt)).lineLimit(4)
                                        Text(.quizGenerateCandidate(card.type.label, card.category.label, card.answer)).lineLimit(2)
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
                .frame(maxHeight: 420)
            }
        } onConfirm: {
            guard model.confirm() else { return }
            saved()
            dismiss()
        }
    }
}
