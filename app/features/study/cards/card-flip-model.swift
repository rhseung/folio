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
    // 참거짓 카드에서 고른 답이다. 고르면 답과 이유를 보이고 다음 카드로 넘어가기를 기다린다.
    private(set) var picked: Bool?
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
        guard let card = current, card.kind == .flip else { return }
        workspace.run(CardFlip(course: courseId, unit: card.unitId, card: card.id, known: isKnown))
        if isKnown { known.append(card.id) } else { unknown.append(card.id) }
        next()
    }

    // 참거짓 카드는 뒤집지 않고 답을 고른다. 맞히면 앎, 틀리면 모름으로 센다.
    func pick(_ answer: Bool) {
        guard let card = current, card.kind == .trueFalse, picked == nil else { return }
        workspace.run(CardFlip(course: courseId, unit: card.unitId, card: card.id, answer: answer))
        if card.knows(picking: answer) { known.append(card.id) } else { unknown.append(card.id) }
        picked = answer
    }

    func next() {
        index += 1
        flipped = false
        picked = nil
    }

    var verdict: (text: String, tone: Tone)? {
        guard let card = current, let picked, let answer = card.answer else { return nil }
        let verdict: Verdict = card.knows(picking: picked) ? .correct : .wrong
        return (String(localized: .noteCardsVerdict(verdict.label, String(localized: answer ? .solveTrue : .solveFalse))), verdict.tone)
    }

    func againUnknown() {
        let again = Set(unknown)
        deck = deck.filter { again.contains($0.id) }
        known = []
        unknown = []
        index = 0
        flipped = false
        picked = nil
    }
}
