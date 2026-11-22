import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class CardsModel {
    struct Group: Identifiable {
        var unit: FolioDomain.Unit
        var depth: Int
        var cards: [CourseStudy.CardRecord]
        var note: String
        var id: UUID { unit.id }
    }

    let workspace: Workspace
    let courseId: UUID
    var onlyUnknown = false
    private(set) var changed: Set<UUID> = []

    init(workspace: Workspace, courseId: UUID) {
        self.workspace = workspace
        self.courseId = courseId
    }

    var study: CourseStudy? { workspace.study(of: courseId) }

    var subtitle: String {
        let cards = study?.allCards ?? []
        return [String(localized: .cardsCount(cards.count)), String(localized: .cardsUnknownCount(cards.filter(\.status.needsWork).count))]
            .joined(separator: " · ")
    }

    var isEmpty: Bool { study?.allCards.isEmpty ?? true }

    var filterOptions: [(Bool, String)] { [(false, String(localized: .solveFilterAll)), (true, String(localized: .cardsUnknown))] }

    // 카드가 없는 단원은 숨기지 않는다. 단원마다 카드를 더할 자리가 있어야 하기 때문이다. 모르는 카드만 볼 때는 숨긴다.
    var groups: [Group] {
        guard let study else { return [] }
        return UnitTree.outline(study.file.units).compactMap { row in
            let all = study.cards(of: row.unit.id)
            let cards = onlyUnknown ? all.filter(\.status.needsWork) : all
            if onlyUnknown, cards.isEmpty { return nil }
            let unknown = all.filter(\.status.needsWork).count
            let note = unknown > 0 ? "\(all.count) · " + String(localized: .cardsUnknownCount(unknown)) : "\(all.count)"
            return Group(unit: row.unit, depth: row.depth, cards: cards, note: note)
        }
    }

    func chip(_ r: CourseStudy.CardRecord) -> (text: String, tone: Tone)? { r.status.cardChip }

    var changeKey: [Int] { [workspace.notesRevision, workspace.studyRevision] }

    func loadChanged() { changed = workspace.changedCardSources(in: courseId) }
}
