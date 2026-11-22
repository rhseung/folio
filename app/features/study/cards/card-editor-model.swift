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

    init(workspace: Workspace, course: LoadedCourse, draft: CardDraft) {
        self.workspace = workspace
        self.course = course
        self.draft = draft
        if let id = draft.original?.id { sourceChanged = workspace.changedCardSources(in: course.id).contains(id) }
        if sourceChanged, let noteId = draft.noteId, let blockId = draft.noteBlockId,
            let note = (try? course.store.notes())?.first(where: { $0.meta.id == noteId }), let text = try? course.store.read(note),
            let block = NoteBlockCard.find(blockId, in: text), let raw = NoteBlockCard.source(of: blockId, in: text)
        {
            source = (block, raw)
        }
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
