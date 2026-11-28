import FolioDomain
import SwiftUI

// 정리 노트 하나의 카드다. 노트 옆 칸에 열어 읽으면서 넘긴다. 과목 열 없이 칸 전체를 쓴다.
struct NoteCardsView: View {
    @State private var model: NoteCardsModel
    @Environment(\.itemSheets) private var sheets
    @Environment(\.openLink) private var openLink
    // 이 칸은 노트 옆에 놓인다. 노트를 누르고 글을 쓰는 동안에는 수식 키 없는 카드의 키(스페이스, T, F)를 듣지 않는다.
    @Environment(\.paneFocused) private var paneFocused

    init(workspace: Workspace, course: LoadedCourse, noteId: UUID) {
        _model = State(initialValue: NoteCardsModel(workspace: workspace, courseId: course.id, noteId: noteId))
    }

    var body: some View {
        if model.exists {
            let groups = model.groups
            let current = paneFocused ? model.current(in: groups) : nil
            Page {
                PageHeader(title: String(localized: .cardsTitle), subtitle: model.subtitle(groups)) {
                    Text(model.noteTitle).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                }
                if groups.isEmpty {
                    EmptyCard(
                        systemImage: "rectangle.on.rectangle", title: String(localized: .noteCardsEmpty),
                        detail: String(localized: .noteCardsEmptyDetail))
                }
                ForEach(groups) { group in
                    Block(title: group.title, note: model.note(group)) {
                        Button(.noteCardsOpenSection, systemImage: "arrow.up.forward") { open(group) }.buttonStyle(.ghost)
                    } content: {
                        VStack(spacing: Theme.Space.m) {
                            ForEach(group.cards, id: \.card.id) { record in
                                NoteCardTile(model: model, record: record, isCurrent: record.card.id == current)
                            }
                        }
                    }
                }
                HStack(spacing: Theme.Space.l) {
                    Button(.noteCardsMake, systemImage: "sparkles") {
                        if let unit = model.unit { sheets.present(.suggestCards(course: model.courseId, unit: unit, note: model.noteId)) }
                    }
                    Button(.cardsAdd, systemImage: "plus") {
                        if let draft = model.draft(in: groups) { sheets.present(.card(course: model.courseId, draft: draft)) }
                    }
                }
                .buttonStyle(.ghost)
                .disabled(model.unit == nil)
            }
            .task(id: model.changeKey) { model.load() }
        } else {
            ContentUnavailableView(String(localized: .noteCardsMissing), systemImage: "questionmark.folder")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Palette.page)
        }
    }

    // 노트가 옆 칸에 열려 있으면 그 칸이 그 절로 가고, 없으면 옆 칸에 연다.
    func open(_ group: NoteCardsModel.Group) {
        model.choose(group)
        openLink(model.link(to: group), in: .beside, course: model.courseId)
    }
}
