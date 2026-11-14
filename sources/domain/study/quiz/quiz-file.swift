import Foundation

public struct QuizFile: Codable, Sendable, Equatable {
    public var unitId: UUID
    public var cards: [QuizCard]

    public init(unitId: UUID, cards: [QuizCard] = []) {
        self.unitId = unitId
        self.cards = cards
    }
}
