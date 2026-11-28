import FolioActions
import FolioDomain
import FolioMarkdown
import Foundation
import Observation

@MainActor @Observable
final class CardEditorModel {
    let workspace: Workspace
    let course: LoadedCourse
    var draft: CardDraft
    var pending: PendingAction?
    private(set) var sourceChanged = false
    // 원본 노트의 지금 블록이다. 블록을 지웠으면 nil이고 원본에 맞출 수 없다.
    private var source: (block: NoteBlockCard, text: String)?
    // 카드를 이은 노트의 절이다. 노트에 잇지 않은 카드에는 없다.
    private(set) var sections: [NoteOutline.Entry] = []

    init(workspace: Workspace, course: LoadedCourse, draft: CardDraft) {
        self.workspace = workspace
        self.course = course
        self.draft = draft
        if let id = draft.original?.id { sourceChanged = workspace.changedCardSources(in: course.id).contains(id) }
        guard let noteId = draft.noteId, let note = course.store.note(id: noteId, in: course.file), let text = try? course.store.read(note)
        else { return }
        if note.format == .markdown { sections = NoteOutline(text).entries }
        if sourceChanged, let blockId = draft.noteBlockId, let block = NoteBlockCard.find(blockId, in: text),
            let raw = NoteBlockCard.source(of: blockId, in: text)
        {
            source = (block, raw)
        }
    }

    var kindOptions: [(CardKind, String)] { CardKind.allCases.map { ($0, $0.label) } }
    var answerOptions: [(Bool, String)] { [(true, String(localized: .solveTrue)), (false, String(localized: .solveFalse))] }
    var frontLabel: String { String(localized: draft.kind == .trueFalse ? .cardsStatement : .cardsFront) }
    var backLabel: String { String(localized: draft.kind == .trueFalse ? .cardsReason : .cardsBack) }

    // 카드가 가리키던 절이 노트에서 없어졌으면 노트 전체에 이은 것으로 보인다.
    var sectionOptions: [(String?, String)] {
        [(nil, String(localized: .noteCardsWholeNote))] + sections.map { (Optional($0.anchor), $0.title) }
    }

    var section: String? {
        get { draft.noteSection.flatMap { anchor in sections.contains { $0.anchor == anchor } ? anchor : nil } }
        set { draft.noteSection = newValue }
    }

    var canRefresh: Bool { source != nil }

    func refreshFromSource() {
        guard let source else { return }
        draft.front = source.block.front
        draft.back = source.block.back
        draft.noteBlockHash = StudyCard.blockHash(source.text)
        sourceChanged = false
    }

    var title: String { String(localized: draft.original == nil ? .cardsAdd : .cardsEdit) }
    var deleteTitle: String? { draft.original == nil ? nil : String(localized: .cardsRemove) }

    var unitOptions: [SelectOption<UUID>] {
        UnitTree.outline(course.file.units).map { SelectOption(id: $0.unit.id, label: $0.unit.title, depth: $0.depth) }
    }

    func confirm() -> Bool {
        let card = draft.card(device: workspace.device, at: workspace.now)
        return workspace.run(CardSave(course: course.id, cards: [card], movedFrom: draft.original?.unitId)) != nil
    }

    func remove(then done: @escaping @MainActor () -> Void) {
        guard let card = draft.original else { return }
        pending = workspace.ask(CardRemove(course: course.id, unit: card.unitId, card: card.id)) { _ in done() }
    }
}
