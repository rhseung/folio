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
                    Block(title: root.title, note: String(localized: .quizCardCount(group.count)), trailing: { addMenu(root) }) {
                        Card { rows(group.entries) }
                    }
                    .contextMenu { addItems(root) }
                } else {
                    Card { rows(group.entries) }
                }
            }
        }
        .sheet(item: $model.editing) { draft in
            CardEditorSheet(workspace: model.workspace, course: course, draft: draft, units: course.file.units) { model.load(course) }
        }
        .confirming($model.pending)
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
                .linkTarget(card.id)
                .opens { model.editing = CardDraft(card) }
                .help(Text(.quizCardEdit))
                .contextMenu { CardMenu(courseId: course.id, card: card) }
            }
        }
    }

    @ViewBuilder func addItems(_ unit: FolioDomain.Unit) -> some View {
        Button(.quizCardsAddManual) { model.editing = CardDraft(unitId: unit.id) }
        Button(.quizCardsAddClaude) { model.generating = unit }
    }

    func addMenu(_ unit: FolioDomain.Unit) -> some View {
        Menu {
            addItems(unit)
        } label: {
            Image(systemName: "plus")
        }
        .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.borderless).pointingHand().fixedSize()
        .foregroundStyle(Theme.Palette.textSecondary)
        .help(Text(.quizCardsAddHelp(unit.title)))
    }
}
