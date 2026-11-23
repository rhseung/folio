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
}
