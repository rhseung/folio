import Foundation

// 단원 하나의 카드다. `.folio/cards/<단원 ID>.json`에 둔다.
public struct CardFile: Codable, Sendable, Equatable {
    public var unitId: UUID
    public var cards: [StudyCard]

    public init(unitId: UUID, cards: [StudyCard] = []) {
        self.unitId = unitId
        self.cards = cards
    }
}
