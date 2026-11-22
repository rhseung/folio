import FolioDomain
import SwiftUI

struct CardsView: View {
    @State private var model: CardsModel
    @Environment(\.itemSheets) private var sheets
    let course: LoadedCourse

    init(workspace: Workspace, course: LoadedCourse) {
        _model = State(initialValue: CardsModel(workspace: workspace, courseId: course.id))
        self.course = course
    }

    var body: some View {
        let groups = model.groups
        Page {
            HStack(alignment: .bottom) {
                PageHeader(title: String(localized: .cardsTitle), subtitle: model.subtitle) { EmptyView() }
                Spacer(minLength: Theme.Space.m)
                Button(.unitsFlip, systemImage: "rectangle.on.rectangle") { sheets.present(.flipCards(course: course.id, unit: nil)) }
                    .buttonStyle(.prominent).disabled(model.isEmpty)
            }
            if course.file.units.isEmpty {
                Card { CardRow(last: true) { EmptyLine(String(localized: .cardsNoUnits)) } }
            } else {
                SegmentedControl(selection: $model.onlyUnknown, options: model.filterOptions)
                ForEach(groups) { group in
                    Block(
                        title: group.unit.title, note: group.note
                    ) {
                        Button(.unitsFlip) { sheets.present(.flipCards(course: course.id, unit: group.unit.id)) }.buttonStyle(.ghost)
                            .disabled(group.cards.isEmpty)
                        Button(.cardsAdd, systemImage: "plus") {
                            sheets.present(.card(course: course.id, draft: CardDraft(unitId: group.unit.id)))
                        }
                        .buttonStyle(.ghost).labelStyle(.iconOnly).help(Text(.cardsAdd))
                    } content: {
                        Card {
                            if group.cards.isEmpty {
                                CardRow(last: true) { EmptyLine(String(localized: .cardsEmptyUnit)) }
                            }
                            ForEach(Array(group.cards.enumerated()), id: \.element.card.id) { i, r in
                                Button {
                                    sheets.present(.card(course: course.id, draft: CardDraft(r.card)))
                                } label: {
                                    CardRow(last: i == group.cards.count - 1) {
                                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                            StudyText(text: r.card.front).lineLimit(2)
                                            StudyText(text: r.card.back).lineLimit(1)
                                                .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                        }
                                        Spacer(minLength: Theme.Space.m)
                                        if model.changed.contains(r.card.id) {
                                            Badge(String(localized: .cardsSourceChanged), tone: .warning)
                                        }
                                        if let chip = model.chip(r) { Badge(chip.text, tone: chip.tone) }
                                    }
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.pointing(.plain))
                                .contextMenu { CardMenu(courseId: course.id, card: r.card) }
                                .linkTarget(r.card.id)
                            }
                        }
                    }
                }
            }
        }
        .task(id: model.changeKey) { model.loadChanged() }
    }
}
