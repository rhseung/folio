import FolioAI
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

    var title: String { String(localized: draft.original == nil ? .quizCardAdd : .quizCardEdit) }
    var deleteTitle: String? { draft.original == nil ? nil : String(localized: .quizCardRemove) }

    func unitOptions(_ units: [FolioDomain.Unit]) -> [PickOption<UUID>] {
        UnitTree.outline(units).map { PickOption(id: $0.unit.id, title: $0.unit.title, depth: $0.depth) }
    }

    func saveCard() -> Bool {
        let card = draft.card(device: workspace.device)
        return workspace.run(QuizCardSave(course: course.id, cards: [card], movedFrom: draft.original?.unitId)) != nil
    }

    func remove(then done: @escaping @MainActor () -> Void) {
        guard let card = draft.original else { return }
        pending = workspace.ask(QuizCardRemove(course: course.id, unit: card.unitId, card: card.id)) { _ in done() }
    }
}
