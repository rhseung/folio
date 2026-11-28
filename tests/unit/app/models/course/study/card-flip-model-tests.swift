import FolioActions
import FolioDomain
import Foundation
import Testing

@testable import Folio

@MainActor
struct CardFlipModelTests {
    @Test func theDeckStaysFixedWhileFlippingAndAgainKeepsOnlyUnknownCards() throws {
        let workspace = try fixtureWorkspace()
        let unit = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        let cards = ["가", "나", "다"].map { StudyCard(device: workspace.device, at: .now, unitId: unit, front: $0, back: "뜻") }
        _ = try workspace.runThrowing(CardSave(course: graphTheory, cards: cards, movedFrom: nil))

        let model = CardFlipModel(workspace: workspace, courseId: graphTheory, unitId: unit)
        #expect(model.title == "매칭")
        let order = model.deck.map(\.id)
        try #require(order.count == 3)
        model.flip()
        model.mark(known: false)
        #expect(!model.flipped && model.deck.map(\.id) == order)
        model.mark(known: true)
        model.mark(known: true)
        #expect(model.isDone)

        model.againUnknown()
        #expect(model.deck.map(\.id) == [order[0]] && model.index == 0 && !model.isDone)
        #expect(workspace.study(of: graphTheory)?.flipDeck(unit: unit).first?.card.id == order[0])
    }

    // 참거짓 카드는 뒤집지 않고 답을 고른다. 고르면 답과 이유를 보이며 기다리고, 맞히면 앎, 틀리면 모름으로 센다.
    @Test func aTrueFalseCardIsAnsweredByPicking() throws {
        let workspace = try fixtureWorkspace()
        let unit = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        let cards = [true, false].map { answer in
            StudyCard(
                device: workspace.device, at: .now, unitId: unit, kind: .trueFalse, front: answer ? "참인 문장" : "거짓인 문장", back: "이유",
                answer: answer)
        }
        _ = try workspace.runThrowing(CardSave(course: graphTheory, cards: cards, movedFrom: nil))

        let model = CardFlipModel(workspace: workspace, courseId: graphTheory, unitId: unit)
        #expect(model.current?.id == cards[0].id && model.verdict == nil)
        // 앞뒤 카드의 길로는 넘어가지 않는다.
        model.mark(known: true)
        #expect(model.index == 0 && model.known.isEmpty)
        model.pick(true)
        #expect(model.picked == true && model.index == 0 && model.verdict?.text == "맞음 · 답은 참")
        // 답을 본 뒤에 다시 고를 수 없다.
        model.pick(false)
        #expect(model.known == [cards[0].id] && model.unknown.isEmpty)
        model.next()
        model.pick(true)
        #expect(model.verdict?.text == "틀림 · 답은 거짓" && model.unknown == [cards[1].id])
        model.next()
        #expect(model.isDone && model.picked == nil)

        let study = try #require(workspace.study(of: graphTheory))
        #expect(study.cards[cards[0].id]?.status == .neverWrong && study.cards[cards[1].id]?.status.isOpen == true)
    }
}
