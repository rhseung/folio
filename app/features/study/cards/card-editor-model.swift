import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class CardEditorModel {
    let workspace: Workspace
    let course: LoadedCourse
    var draft: CardDraft
    var pending: PendingAction?

    init(workspace: Workspace, course: LoadedCourse, draft: CardDraft) {
        self.workspace = workspace
        self.course = course
        self.draft = draft
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
