import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class CardFlipModel {
    let workspace: Workspace
    let courseId: UUID
    let unitId: UUID?
    // 넘기는 동안 덱 순서를 고정한다. 기록할 때마다 상태가 바뀌어 순서를 다시 정하면 같은 카드가 또 나오기 때문이다.
    private(set) var deck: [StudyCard]
    var index = 0
    var flipped = false
    private(set) var known: [UUID] = []
    private(set) var unknown: [UUID] = []

    init(workspace: Workspace, courseId: UUID, unitId: UUID?, scope: [UUID]? = nil) {
        self.workspace = workspace
        self.courseId = courseId
        self.unitId = unitId
        let study = workspace.study(of: courseId)
        deck = (scope.map { study?.flipDeck(scope: $0) } ?? study?.flipDeck(unit: unitId))?.map(\.card) ?? []
    }

    var title: String {
        let unit = unitId.flatMap { id in workspace.course(courseId)?.file.units.first { $0.id == id }?.title }
        return unit ?? String(localized: .cardsFlipTitle)
    }

    var current: StudyCard? { deck.indices.contains(index) ? deck[index] : nil }
    var isDone: Bool { !deck.isEmpty && index >= deck.count }
    var progress: String { String(localized: .cardsFlipProgress(min(index + 1, deck.count), deck.count)) }
    var resultLine: String { String(localized: .cardsFlipResult(known.count, unknown.count)) }

    func flip() { flipped.toggle() }

    func mark(known isKnown: Bool) {
        guard let card = current else { return }
        workspace.run(CardFlip(course: courseId, unit: card.unitId, card: card.id, known: isKnown))
        if isKnown { known.append(card.id) } else { unknown.append(card.id) }
        index += 1
        flipped = false
    }

    func againUnknown() {
        let again = Set(unknown)
        deck = deck.filter { again.contains($0.id) }
        known = []
        unknown = []
        index = 0
        flipped = false
    }
}
